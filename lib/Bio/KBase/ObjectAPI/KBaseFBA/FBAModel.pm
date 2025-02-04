########################################################################
# Bio::KBase::ObjectAPI::KBaseFBA::FBAModel - This is the moose object corresponding to the Model object
# Authors: Christopher Henry, Scott Devoid, Paul Frybarger
# Contact email: chenry@mcs.anl.gov
# Development location: Mathematics and Computer Science Division, Argonne National Lab
# Date of module creation: 2012-03-26T23:22:35
########################################################################
package Bio::KBase::ObjectAPI::KBaseFBA::FBAModel;

use YAML::XS;
use File::Temp;
use Bio::KBase::ObjectAPI::KBaseFBA::DB::FBAModel;
use Moose;
use namespace::autoclean;
use Class::Autouse qw(
    Graph::Undirected
);
use Bio::KBase::ObjectAPI::utilities;
extends 'Bio::KBase::ObjectAPI::KBaseFBA::DB::FBAModel';
#***********************************************************************************************************
# ADDITIONAL ATTRIBUTES:
#***********************************************************************************************************
has features => ( is => 'rw', isa => 'ArrayRef',printOrder => '-1', type => 'msdata', metaclass => 'Typed', lazy => 1, builder => '_buildfeatures' );
has featureHash => ( is => 'rw', isa => 'HashRef',printOrder => '-1', type => 'msdata', metaclass => 'Typed', lazy => 1, builder => '_buildfeatureHash' );
has compound_reaction_hash => ( is => 'rw', isa => 'HashRef',printOrder => '-1', type => 'msdata', metaclass => 'Typed', lazy => 1, builder => '_buildcompound_reaction_hash' );

#***********************************************************************************************************
# BUILDERS:
#***********************************************************************************************************
sub _buildcompound_reaction_hash {
	my ($self) = @_;
	my $hash = {};
	my $rxns = $self->modelreactions();
	foreach my $rxn (@{$rxns}) {
		my $rgts = $rxn->modelReactionReagents();
		foreach my $rgt (@{$rgts}) {
			$hash->{$rgt->modelcompound()->id()}->{$rxn->id()} = $rgt->coefficient();
		}
	}
	return $hash;
}

sub _buildfeatures {
	my ($self) = @_;
	#Retrieving list of genes in model
	my $rxns = $self->modelreactions();
	my $ftrhash = {};
	for (my $i=0; $i < @{$rxns};$i++) {
		my $rxn = $rxns->[$i];
		my $ftrs = $rxn->featureIDs();
		foreach my $ftr (@{$ftrs}) {
			$ftrhash->{$ftr} = 1;
		}
	}
	return [keys(%{$ftrhash})];
}

sub _buildfeatureHash {
	my ($self) = @_;
	my $ftrhash = {};
	my $rxns = $self->modelreactions();
	for (my $i=0; $i < @{$rxns};$i++) {
		my $rxn = $rxns->[$i];
		my $ftrs = $rxn->featureUUIDs();
		foreach my $ftr (@{$ftrs}) {
			$ftrhash->{$ftr}->{$rxn->_reference()} = $rxn;
		}
	}
	return $ftrhash;
}

#***********************************************************************************************************
# CONSTANTS:
#***********************************************************************************************************

#***********************************************************************************************************
# FUNCTIONS:
#***********************************************************************************************************
sub predict_auxotrophy_nofba {
	my ($self) = @_;
	my $thresholds = Bio::KBase::constants::auxotrophy_thresholds();
	my $output = {};
	foreach my $cpd (keys(%{$thresholds})) {
		my $rule = $thresholds->{$cpd}->[3];
		my $steps = [split(/\&/,$rule)];
		$output->{$cpd} = {
			gfrxn => 0,
			missing => 0,
			present => 0,
			total => 0,
			missing_reactions => [],
			gapfilled_reactions => [],
			present_reactions => [],
		};
		foreach my $step (@{$steps}) {
			my $options = [split(/\|/,$step)];
			my $bestscore;
			my $bestcounts = [0,0,0];
			my $bestmissing = [];
			my $bestgapfilled = [];
			my $bestpresent = [];
			foreach my $option (@{$options}) {
				my $subcounts = [0,0,0];
				my $submissing = [];
				my $subgapfilled = [];
				my $subpresent = [];
				my $count = 0;
				my $substeps = [split(/\+/,$option)];
				foreach my $substep (@{$substeps}) {
					$count++;
					my $alternatives = [split(/\//,$substep)];
					my $status = "missing";
					my $selected_rxn = $alternatives->[0];
					foreach my $alternative (@{$alternatives}) {
						my $diff = 5-length($alternative);
						my $prefix = "rxn";
						for (my $i=0; $i < $diff; $i++) {
							$prefix .= "0";
						}
						my $mdlrxn = $self->getObject("modelreactions",$prefix.$alternative."_c0");
						if (defined($mdlrxn)) {
							if (length($mdlrxn->gapfillString()) > 0 && $status ne "present") {
								$status = "gapfilled";
								$selected_rxn = $alternative;
							} else {
								$selected_rxn = $alternative;
								$status = "present";
							}
						}
					}
					if ($status eq "missing") {
						$subcounts->[0]++;
						push(@{$submissing},$selected_rxn);
					} elsif ($status eq "gapfilled") {
						$subcounts->[1]++;
						push(@{$subgapfilled},$selected_rxn);
					} else {
						$subcounts->[2]++;
						push(@{$subpresent},$selected_rxn);
					}
				}
				my $score = ($subcounts->[0]+$subcounts->[1])/$count;
				if (!defined($bestscore) || $bestscore > $score) {
					$bestscore = $score;
					$bestcounts = $subcounts;
					$bestmissing = $submissing;
					$bestgapfilled = $subgapfilled;
					$bestpresent = $subpresent;
				}
			}
			$output->{$cpd}->{gfrxn} += $bestcounts->[1];
			$output->{$cpd}->{missing} += $bestcounts->[0];
			$output->{$cpd}->{present} += $bestcounts->[2];
			$output->{$cpd}->{total} += $bestcounts->[0]+$bestcounts->[1]+$bestcounts->[2];
			push(@{$output->{$cpd}->{missing_reactions}},@{$bestmissing});
			push(@{$output->{$cpd}->{gapfilled_reactions}},@{$bestgapfilled});
			push(@{$output->{$cpd}->{present_reactions}},@{$bestpresent});
		}
	}
	return $output;
}

sub load_metabolite_hashes {
	my ($self,$args) = @_;
	$args = Bio::KBase::utilities::args($args,["priority"],{
		compartment => "c",
		compartment_index => 0,
		priority => 0,
		hashes => {
			ids => {},
			names => {},
			structures => {},
			base_structures => {},
			formulas => {}
		}
	});
	my $cmp = $args->{compartment};
	my $priority = $args->{priority};
	my $cpds = $self->modelcompounds();
	for (my $i=0; $i < @{$cpds}; $i++) {
		if ($cpds->[$i]->modelcompartment()->compartment()->id() eq $cmp) {
			if ($cpds->[$i]->id() =~ m/(cpd\d+)/) {
				my $msid = $1;
				my $cpdhash = Bio::KBase::utilities::compound_hash();
				if (defined($cpdhash->{$msid}->{names})) {
					for (my $j=0; $j < @{$cpdhash->{$msid}->{names}}; $j++) {
						$args->{hashes}->{names}->{Bio::KBase::utilities::nameToSearchname($cpdhash->{$msid}->{names}->[$j])}->{$cpds->[$i]->id()} = $priority;
					}
				}
				$args->{hashes}->{ids}->{$msid}->{$cpds->[$i]->id()} = $priority;
			} elsif ($cpds->[$i]->id() =~ m/(^.+)_[a-z]\d+/) {
				$args->{hashes}->{ids}->{$1}->{$cpds->[$i]->id()} = $priority;
			}
			if (defined($cpds->[$i]->inchikey()) && length($cpds->[$i]->inchikey()) > 0) {
				$args->{hashes}->{structures}->{$cpds->[$i]->inchikey()}->{$cpds->[$i]->id()} = $priority;
				my $array = [split(/[_-]/,$cpds->[$i]->inchikey())];
				$args->{hashes}->{base_structures}->{$array->[0]}->{$cpds->[$i]->id()} = $priority;
			}
			if (defined($cpds->[$i]->smiles()) && length($cpds->[$i]->smiles()) > 0) {
				$args->{hashes}->{structures}->{$cpds->[$i]->smiles()}->{$cpds->[$i]->id()} = $priority;
			}
			if (defined($cpds->[$i]->formula()) && length($cpds->[$i]->formula()) > 0) {
				$args->{hashes}->{formulas}->{$cpds->[$i]->neutral_formula()}->{$cpds->[$i]->id()} = $priority;
			}
			if (defined($cpds->[$i]->name()) && length($cpds->[$i]->name()) > 0) {
				$args->{hashes}->{names}->{Bio::KBase::utilities::nameToSearchname($cpds->[$i]->name())}->{$cpds->[$i]->id()} = $priority;
			}
		}
	}
}

sub addPhenotypeTransporters {
	my $self = shift;
	my $args = Bio::KBase::ObjectAPI::utilities::args(["phenotypes"], {
		positiveonly => 0,
		extracellular_compartments => [0],
		cytosol_compartments => undef
	}, @_);
	#Retrieving list of compartments in model
	my $mdlcmps = $self->modelcompartments();
	if (!defined($args->{cytosol_compartments})) {
		my $cmphash = {};
		for (my $i=0; $i < @{$mdlcmps}; $i++) {
			if ($mdlcmps->[$i]->compartment()->id() eq "c") {
				$cmphash->{$mdlcmps->[$i]->compartmentIndex()} = 1;
			}
		}
		$args->{cytosol_compartments} = [keys(%{$cmphash})];
	}
	if (!defined($args->{extracellular_compartments})) {
		my $cmphash = {};
		for (my $i=0; $i < @{$mdlcmps}; $i++) {
			if ($mdlcmps->[$i]->compartment()->id() eq "e") {
				$cmphash->{$mdlcmps->[$i]->compartmentIndex()} = 1;
			}
		}
		$args->{extracellular_compartments} = [keys(%{$cmphash})];
	}
	#Building hash of phenotype transporters	
	my $phenotypes = $args->{phenotypes}->phenotypes();
	my $mediahash;
	for (my $i=0; $i < @{$phenotypes}; $i++) {
		my $phenotype = $phenotypes->[$i];
		my $media = $phenotype->media();
		if ($phenotype->normalizedGrowth() > 0 || $args->{positiveonly} == 0) {
			$mediahash->{$media->_reference()} = $media;
		} 
	}
	my $cpdhash;
	foreach my $ref (keys(%{$mediahash})) {
		my $cpds = $mediahash->{$ref}->mediacompounds();
		foreach my $cpd (@{$cpds}) {
			$cpdhash->{$cpd->compound()->id()} = $cpd;
		}
	}
	#Identifying which compounds are transported in all compartments
	my $needed = {};
	my $compound_reactions = $self->compound_reaction_hash();
	foreach my $cpd (keys(%{$cpdhash})) {
		for (my $i=0; $i < @{$args->{cytosol_compartments}}; $i++) {
			for (my $j=0; $j < @{$args->{extracellular_compartments}}; $j++) {
				my $found = 0;
				if (defined($compound_reactions->{$cpd."_e".$args->{extracellular_compartments}->[$j]})) {
					foreach my $rxn (keys(%{$compound_reactions->{$cpd."_e".$args->{extracellular_compartments}->[$j]}})) {
						if (defined($compound_reactions->{$cpd."_c".$args->{cytosol_compartments}->[$i]}->{$rxn})
							&& 	$compound_reactions->{$cpd."_c".$args->{cytosol_compartments}->[$i]}->{$rxn}*$compound_reactions->{$cpd."_e".$args->{extracellular_compartments}->[$j]}->{$rxn} < 0) {
							$found = 1;
							last;
						}
					}		
				
				}
				if ($found == 0) {
					$needed->{$cpd}->{$args->{extracellular_compartments}->[$j]}->{$args->{cytosol_compartments}->[$i]} = 1;
				}
			}
		}
	}
	#Adding transporters to model
	foreach my $cpd (keys(%{$needed})) {
		for my $ext_comp (keys(%{$needed->{$cpd}})) {
			for my $cyt_comp (keys(%{$needed->{$cpd}->{$ext_comp}})) {
				$self->addModelReaction({
					reaction => $cpd."-".$ext_comp."-trans",
					equation => $cpd."_e".$ext_comp." => ".$cpd."_c".$cyt_comp,
					compartment => "c",
					compartmentIndex => $cyt_comp,
					addReaction => 1,
				});
			}
		}
	}
}

sub EnsureProperATPProduction {
	my $self = shift;
	my $args = Bio::KBase::ObjectAPI::utilities::args([],{
		anaerobe => 0,
		max_objective_limit => 1.4,
		media => "RefGlucoseMinimal"
	}, @_);
	my $oldtemplate = $self->template();
	#Need to instantiate compound and reaction objects before swapping out the template
	my $mdlcpds = $self->modelcompounds();
	for (my $i=0; $i < @{$mdlcpds}; $i++) {
		$mdlcpds->[$i]->compound();
	}
	my $mdlrxns = $self->modelreactions();
	for (my $i=0; $i < @{$mdlrxns}; $i++) {
		$mdlrxns->[$i]->reaction();
	}
	my $template_trans = Bio::KBase::constants::template_trans();
	my $currentcore = $self->getLinkedObject(Bio::KBase::utilities::conf("ModelSEED","default_template_workspace")."/".$template_trans->{core});
	my $legacycore = $self->getLinkedObject(Bio::KBase::utilities::conf("ModelSEED","default_template_workspace")."/".$template_trans->{legacycore});
	my $matches = 0;
	my $legacymatches = 0;
	my $corerxns = $currentcore->reactions();
	for (my $i=0; $i < @{$corerxns}; $i++) {
		if (defined($oldtemplate->getObject("reactions",$corerxns->[$i]->id()))) {
			$matches++;
		}
	}
	$corerxns = $legacycore->reactions();
	for (my $i=0; $i < @{$corerxns}; $i++) {
		if (defined($oldtemplate->getObject("reactions",$corerxns->[$i]->id()))) {
			$legacymatches++;
		}
	}
	if ($matches > $legacymatches) {
		print $matches."\t".$legacymatches."\tCurrent core\n";
		$self->template($currentcore);
	} else {
		print $matches."\t".$legacymatches."\tLegacy core\n";
		$self->template($legacycore);
	}
	#Retrieving and hashing core reactions
	my $rxnhash = {};
	$corerxns = $self->template()->reactions();
	for (my $i=0; $i < @{$corerxns}; $i++) {
		$rxnhash->{$corerxns->[$i]->msid()} = $corerxns->[$i]->direction();
	}
	#Removing noncore reactions temporarily
	$mdlrxns = $self->modelreactions();
	my $removedrxn = [];
	for (my $i=0; $i < @{$mdlrxns}; $i++) {
		my $id = $mdlrxns->[$i]->id();
		if ($mdlrxns->[$i]->id() =~ m/(rxn\d+)/) {
			$id = $1;
		}
		if (!defined($rxnhash->{$id})) {
			push(@{$removedrxn},$mdlrxns->[$i]);
			$self->remove("modelreactions",$mdlrxns->[$i]);
		} elsif (defined($rxnhash->{$id})) {
			$mdlrxns->[$i]->direction($rxnhash->{$1});
		}
	}
	#Removing and blacklisting aerobic reactions if model is anaerobic
	my $blacklist = [];
	if ($args->{anaerobe} == 1) {
		my $mdlrxn = $self->getObject("modelreactions","rxn14419_c0");
		if (defined($mdlrxn)) {
			$self->remove("modelreactions",$mdlrxn);
		}
		$mdlrxn = $self->getObject("modelreactions","rxn14422_c0");
		if (defined($mdlrxn)) {
			$self->remove("modelreactions",$mdlrxn);
		}
		$blacklist = ["rxn14426","rxn14419","rxn14422"];
	}
	#Gapfilling to ensure the core model can make ATP
	my $object = Bio::KBase::constants::atp_hydrolysis_biomass();
	my $count = @{$self->biomasses()};
	$object->{id} = "bio".($count+1);
	my $biorxn = $self->add("biomasses",$object);
	$self->_reference("NULL/".$self->id());
	my $output = Bio::KBase::ObjectAPI::functions::func_gapfill_metabolic_model({
		workspace => "NULL",
		fbamodel_id => $self->id(),
		fbamodel_output_id => $self->id().".coregf",
		target_reaction => $biorxn->id(),
		media_workspace => Bio::KBase::utilities::conf("ModelSEED","default_media_workspace"),
		media_id => "RefGlucoseMinimal",
		atp_production_check => 0,
		#base_atp_production => 260,
		blacklist => $blacklist
	},{fbamodel => $self});
	$self->attributes()->{core_gapfilling} = $output->{number_gapfilled_reactions}+0;
	#Restoring the template
	$self->template($oldtemplate);
	#Adding noncore reactions back into the model
	my $removerxnid = [];
	for (my $i=0; $i < @{$removedrxn}; $i++) {
		$self->add("modelreactions",$removedrxn->[$i]);
		push(@{$removerxnid},$removedrxn->[$i]->id());
	}
	#Removing any noncore reactions that cause overproduction of ATP
	my $datachannel = {
		fbamodel => $self
	};
	Bio::KBase::ObjectAPI::functions::func_run_flux_balance_analysis({
		workspace => "NULL",
		fbamodel_id => $self->id(),
		fba_output_id => $self->id().".atp.fba",
		media_id => $args->{media},
		media_workspace => Bio::KBase::utilities::conf("ModelSEED","default_media_workspace"),
		target_reaction => $biorxn->id(),
		reaction_addition_study => 1,
		max_objective_limit => $args->{max_objective_limit},
		reaction_list => $removerxnid
	},$datachannel);
	my $rxn_addition_data = $datachannel->{fba}->outputfiles()->{ReactionAdditionAnalysis};
	my $first = 1;
	$self->attributes()->{base_rejected_reactions} = 0;
	if (defined($rxn_addition_data)) {
		for (my $i=1; $i < @{$rxn_addition_data}; $i++) {
			my $row = [split(/\t/,$rxn_addition_data->[$i])];
			if ($row->[2] == 0) {
				if ($row->[1] =~ m/(.)(rxn.+)/) {
					 print "Removing:".$row->[1]."\n";
					 my $sign = $1;
					 my $id = $2;
					 $first = 0;
					 my $rxnobj = $self->queryObject("modelreactions",{id => $id});
					 if ($sign eq "+") {
					 	if ($rxnobj->direction() eq "=") {
					 		$rxnobj->direction("<");
					 	} else {
					 		$self->remove("modelreactions",$rxnobj);
					 	}
					 } else {
					 	if ($rxnobj->direction() eq "=") {
					 		$rxnobj->direction(">");
					 	} else {
					 		$self->remove("modelreactions",$rxnobj);
					 	}
					 }
				}
				$self->attributes()->{base_rejected_reactions}++;
			} else {
				if (!defined($self->attributes()->{initial_atp})) {
					$self->attributes()->{initial_atp} = $row->[0]+0;
				}
				$self->attributes()->{base_atp} = $row->[0]+0;
			}
		}
	}
	#Removing ATP biomass again
	$self->remove("biomasses",$biorxn);
}

sub ComputePathwayAttributes {
	my $self = shift;
	my $classhash = shift;
	my $attributes = $self->attributes();
	my $rxns = $self->modelreactions();
	my $pathwayhash = Bio::KBase::utilities::pathway_hash();
	my $rxnhash = Bio::KBase::utilities::reaction_hash();
	for (my $i=0; $i < @{$rxns}; $i++) {
		if ($rxns->[$i]->id() =~ m/(rxn\d+)/) {
			my $rxnid = $1;
			if (defined($rxnhash->{$rxnid}) && defined($rxnhash->{$rxnid}->{kegg_pathways})) {
				for (my $j=0; $j < @{$rxnhash->{$rxnid}->{kegg_pathways}}; $j++) {
					my $pathid = $rxnhash->{$rxnid}->{kegg_pathways}->[$j];
					$pathid =~ s/[a-z]//g;
					if (defined($pathwayhash->{$pathid})) {
						if (!defined($attributes->{pathways}->{$pathid})) {
							$attributes->{pathways}->{$pathid} = {
								id => $pathid,
 								source => $pathwayhash->{$pathid}->{source},
							    	name => $pathwayhash->{$pathid}->{name},
							    classes => $pathwayhash->{$pathid}->{classes},
							    	reactions => {},
							    	gapfilled_rxn => 0,
							    functional_rxn => 0,
							    nonfunctional_rxn => 0,
							    pathway_size => @{$pathwayhash->{$pathid}->{reactions}}+0,
							    	is_present => 0,#Set in second pass
							    gene_count => 0,
							    average_genes_per_reaction => 0,#Correct in second pass
							    	stddev_genes_per_reaction => 0,#Set in second pass
							    	average_coverage_per_reaction => 0,#Correct in second pass
							    	stddev_coverage_per_reaction => 0,#Set in second pass
							    	featurehash => {},#Delete in second pass
							    	coverages => [],#Delete in second pass
							    	genecounts => []#Delete in second pass
							};
						}
						if (length($rxns->[$i]->gapfillString()) > 0) {
							$attributes->{pathways}->{$pathid}->{gapfilled_rxn}++;
							$attributes->{pathways}->{$pathid}->{reactions}->{$rxnid} = "g";
						} elsif (defined($classhash->{$rxnid}->{comp}) && $classhash->{$rxnid}->{comp} ne "Blocked") {
							$attributes->{pathways}->{$pathid}->{functional_rxn}++;
							$attributes->{pathways}->{$pathid}->{reactions}->{$rxnid} = "a";
						} else {
							$attributes->{pathways}->{$pathid}->{nonfunctional_rxn}++;
							$attributes->{pathways}->{$pathid}->{reactions}->{$rxnid} = "b";
						}
						if ($self->type() eq "Metagenome") {
							if (defined($rxns->[$i]->gene_count())) {
								$attributes->{pathways}->{$pathid}->{gene_count} += $rxns->[$i]->gene_count();
								$attributes->{pathways}->{$pathid}->{average_genes_per_reaction} += $rxns->[$i]->gene_count();
								$attributes->{pathways}->{$pathid}->{average_coverage_per_reaction} += $rxns->[$i]->coverage();
								push(@{$attributes->{pathways}->{$pathid}->{genecounts}},$rxns->[$i]->gene_count());
								push(@{$attributes->{pathways}->{$pathid}->{coverages}},$rxns->[$i]->coverage());
							}
						} else {
							my $ftrids = $rxns->[$i]->featureIDs();
							$attributes->{pathways}->{$pathid}->{average_genes_per_reaction} += @{$ftrids};
							push(@{$attributes->{pathways}->{$pathid}->{genecounts}},@{$ftrids});
							foreach my $ftrid (@{$ftrids}) {
								$attributes->{pathways}->{$pathid}->{featurehash}->{$ftrid} = 1;
							}
						}
					}
				}
			}
		}
	}
	foreach my $pathid (keys(%{$attributes->{pathways}})) {
		$attributes->{pathways}->{$pathid}->{is_present} = 0;
		if ($attributes->{pathways}->{$pathid}->{gene_count} == 0) {
			$attributes->{pathways}->{$pathid}->{gene_count} = keys(%{$attributes->{pathways}->{$pathid}->{featurehash}});
		}
		if (defined($attributes->{pathways}->{$pathid}->{coverages})) {
			my $count = @{$attributes->{pathways}->{$pathid}->{coverages}};
			if ($count > 0) {
				$attributes->{pathways}->{$pathid}->{average_genes_per_reaction} = $attributes->{pathways}->{$pathid}->{average_genes_per_reaction}/$count;
				foreach my $gcount (@{$attributes->{pathways}->{$pathid}->{coverages}}) {
					$attributes->{pathways}->{$pathid}->{stddev_coverage_per_reaction} += ($attributes->{pathways}->{$pathid}->{average_genes_per_reaction} - $gcount)*($attributes->{pathways}->{$pathid}->{average_genes_per_reaction} - $gcount);
				}
				$attributes->{pathways}->{$pathid}->{stddev_coverage_per_reaction} = $attributes->{pathways}->{$pathid}->{stddev_coverage_per_reaction}/$count;
				$attributes->{pathways}->{$pathid}->{stddev_coverage_per_reaction} = sqrt($attributes->{pathways}->{$pathid}->{stddev_coverage_per_reaction});
			}
		}
		my $count = @{$attributes->{pathways}->{$pathid}->{genecounts}};
		if ($count > 0) {
			$attributes->{pathways}->{$pathid}->{average_coverage_per_reaction} = $attributes->{pathways}->{$pathid}->{average_coverage_per_reaction}/$count;
			foreach my $cov (@{$attributes->{pathways}->{$pathid}->{coverages}}) {
				$attributes->{pathways}->{$pathid}->{stddev_genes_per_reaction} += ($attributes->{pathways}->{$pathid}->{average_coverage_per_reaction} - $cov)*($attributes->{pathways}->{$pathid}->{average_coverage_per_reaction} - $cov);
			}
			$attributes->{pathways}->{$pathid}->{stddev_genes_per_reaction} = $attributes->{pathways}->{$pathid}->{stddev_genes_per_reaction}/$count;
			$attributes->{pathways}->{$pathid}->{stddev_genes_per_reaction} = sqrt($attributes->{pathways}->{$pathid}->{stddev_genes_per_reaction});
		}
		if ($attributes->{pathways}->{$pathid}->{functional_rxn} >= 3) {#TODO - need a better way to do this
			$attributes->{pathways}->{$pathid}->{is_present} = 1;
		}
		delete $attributes->{pathways}->{$pathid}->{featurehash};
		delete $attributes->{pathways}->{$pathid}->{coverages};
		delete $attributes->{pathways}->{$pathid}->{genecounts};
	}
}

sub gene_count {
	my $self = shift;
	my $ftrhash = {};
	my $rxns = $self->modelreactions();
	for (my $i=0; $i < @{$rxns};$i++) {
		my $rxn = $rxns->[$i];
		my $ftrs = $rxn->featureUUIDs();
		foreach my $ftr (@{$ftrs}) {
			$ftrhash->{$ftr}->{$rxn->_reference()} = $rxn;
		}
	}
	my $count = keys(%{$ftrhash});
	return $count;
}

sub initialize_attributes {
	my $self = shift;
	my $attributes = $self->attributes();
	if (!defined($attributes->{gene_count})) {
		$attributes->{gene_count} = $self->gene_count();
	}
	if (!defined($attributes->{fbas})) {
		$attributes->{fbas} = {};
	}
	if (!defined($attributes->{auxotrophy})) {
		$attributes->{auxotrophy} = {};
	}
	if (!defined($attributes->{pathways})) {
		$attributes->{pathways} = {};
	}
}

sub gapfilled_reaction_count {
	my $self = shift;
	my $reactions = $self->modelreactions();
	my $count = 0;
	for (my $i=0; $i < @{$reactions}; $i++) {
		my $gfhash = $reactions->[$i]->gapfill_data();
		my $numkeys = keys(%{$gfhash});
		if ($numkeys > 0) {
			$count++;
		}
	}
	return $count;
}

sub gene_associated_reaction_count {
	my $self = shift;
	my $reactions = $self->modelreactions();
	my $count = 0;
	for (my $i=0; $i < @{$reactions}; $i++) {
		my $rxnprots = $reactions->[$i]->modelReactionProteins();
		if (@{$rxnprots} > 0) {
			$count++;
		}
	}
	return $count;
}

sub remove_all_gapfilled_reactions {
	my $self = shift;
	my $reactions = $self->modelreactions();
	my $removelist = [];
	for (my $i=0; $i < @{$reactions}; $i++) {
		if (length($reactions->[$i]->gapfillString()) > 0) {
			push(@{$removelist},$reactions->[$i]);
		}
	}
	for (my $i=0; $i < @{$removelist}; $i++) {
		$self->remove("modelreactions",$removelist->[$i]);
	}
}

sub biomass_compound_count {
	my $self = shift;
	my $bios = $self->biomasses();
	my $biohash;
	for (my $i=0; $i < @{$bios}; $i++) {
		my $biocpds = $bios->[$i]->biomasscompounds();
		for (my $j=0; $j < @{$biocpds}; $j++) {
			$biohash->{$biocpds->[$j]->modelcompound_ref()} = 1;
		}
	}
	my $count = keys(%{$biohash});
	return $count;
}

sub integrated_gapfill_count {
	my $self = shift;
	my $gfs = $self->gapfillings();
	my $count = 0;
	for (my $i=0; $i < @{$gfs}; $i++) {
		if ($gfs->[$i]->integrated() == 1) {
			$count++;
		}
	}
	return $count;
}

sub unintegrated_gapfill_count {
	my $self = shift;
	my $gfs = $self->gapfillings();
	my $count = 0;
	for (my $i=0; $i < @{$gfs}; $i++) {
		if ($gfs->[$i]->integrated() == 0) {
			$count++;
		}
	}
	return $count;
}

=head3 addCompartmentToModel

Definition:
	Bio::KBase::ObjectAPI::KBaseFBA::FBAModel = Bio::KBase::ObjectAPI::KBaseFBA::FBAModel->addCompartmentToModel({
		Compartment => REQUIRED,
		pH => 7,
		potential => 0,
		compartmentIndex => 0
	});
Description:
	Adds a compartment to the model after checking that the compartment isn't already there

=cut
#REFACTOR NEEDED HERE
sub addCompartmentToModel {
    my $self = shift;
    my $args = Bio::KBase::ObjectAPI::utilities::args(["compartment"],{
		pH => 7,
		potential => 0,
		compartmentIndex => 0
	}, @_);
	my $mdlcmp = $self->queryObject("modelcompartments",{compartment_ref => $args->{compartment}->_reference(),compartmentIndex => $args->{compartmentIndex}});
	if (!defined($mdlcmp)) {
		$mdlcmp = $self->add("modelcompartments",{
			id => $args->{compartment}->id().$args->{compartmentIndex},
			compartment_ref => $args->{compartment}->_reference(),
			label => $args->{compartment}->name()."_".$args->{compartmentIndex},
			pH => $args->{pH},
			compartmentIndex => $args->{compartmentIndex},
		});
	}
	return $mdlcmp;
}

=head3 addCompoundToModel

Definition:
	Bio::KBase::ObjectAPI::KBaseFBA::ModelCompound = Bio::KBase::ObjectAPI::KBaseFBA::ModelCompound->addCompoundToModel({
		compound => REQUIRED,
		modelCompartment => REQUIRED,
		charge => undef (default values will be pulled from input compound),
		formula => undef (default values will be pulled from input compound)
	});
Description:
	Adds a compound to the model after checking that the compound isn't already there

=cut
#REFACTOR NEEDED HERE
sub addCompoundToModel {
    my $self = shift;
	my $args = Bio::KBase::ObjectAPI::utilities::args(["compound","modelCompartment"],{
		charge => undef,
		formula => undef
	}, @_);
	my $cpdid = $args->{compound}->id()."_".$args->{modelCompartment}->id();
	my $mdlcpd = $self->getObject("modelcompounds",$cpdid);
	if (!defined($mdlcpd)) {
		if (!defined($args->{charge})) {
			$args->{charge} = $args->{compound}->defaultCharge();
		}
		if (!defined($args->{formula})) {
			$args->{formula} = $args->{compound}->formula();
		}
		$mdlcpd = $self->add("modelcompounds",{
			id => $args->{compound}->id()."_".$args->{modelCompartment}->id(),
			modelcompartment_ref => "~/modelcompartments/id/".$args->{modelCompartment}->id(),
			compound_ref => $args->{compound}->_reference(),
			charge => $args->{charge},
			formula => $args->{formula},
			inchikey => $args->{inchikey},
			smiles => $args->{smiles}
		});
	}
	return $mdlcpd;
}

=head3 adjustBiomassReaction

Definition:
	Bio::KBase::ObjectAPI::KBaseFBA::FBAModel->adjustBiomassReaction({
		biomass => string
		compound => string,
		compartment => string,
		compartmentIndex => integer,
		coefficient => float
	});
Description:
	Modifies the biomass reaction to adjust a compound, add a compound, or remove a compound

=cut
#REFACTOR NEEDED HERE
sub adjustBiomassReaction {
	print("Adjust biomass\n");
    my $self = shift;
    my $args = Bio::KBase::ObjectAPI::utilities::args([],{
    	compound => undef,
    	coefficient => undef,
    	biomass => "bio1",
    	compartment => "c",
    	compartmentIndex => 0,
    	compounds => {},
    	equation => undef
    }, @_);
    my $bio = $self->searchForBiomass($args->{biomass});
	if (defined($args->{equation})) {
		if (!defined($bio)) {
			$bio = $self->add("biomasses",{
				id => $args->{biomass},
				name => "Biomass",
				other => 1,
				dna => 0,
				rna => 0,
				protein => 0,
				cellwall => 0,
				lipid => 0,
				cofactor => 0,
				energy => 0,
				biomasscompounds => []
			});
		}
		$self->LoadExternalReactionEquation({biomass => $bio,equation => $args->{equation},compounds => $args->{compounds}});
	} else {
		if (!defined($bio)) {
	    	Bio::KBase::ObjectAPI::utilities::error("Biomass ".$args->{biomass}." not found!");
	    }
		my $mdlcpd = $self->searchForCompound($args->{compound},$args->{compartment},$args->{compartmentIndex});
	    if (!defined($mdlcpd)) {
	    	my $cpdobj = $self->template()->searchForCompound($args->{compound});
	    	if (!defined($cpdobj)) {
	    		Bio::KBase::ObjectAPI::utilities::error("Compound ".$args->{compound}." not found!");
	    	}
	    	my $mdlcmp = $self->getObject("modelcompartments",$args->{compartment}.$args->{compartmentIndex});
	    	if (!defined($mdlcmp)) {
	    		my $cmp = $self->template()->searchForCompartment($args->{compartment});
		    	if (!defined($cmp)) {
		    		Bio::KBase::ObjectAPI::utilities::error("Unrecognized compartment in equation:".$args->{compartment}."!");
		    	}
	    		$mdlcmp = $self->add("modelcompartments",{
	    			id => $args->{compartment}.$args->{compartmentIndex},
					compartment_ref => $cmp->_reference(),
					compartmentIndex => $args->{compartmentIndex},
					label => $args->{compartment}.$args->{compartmentIndex},
					pH => 7,
					potential => 0,
	    		});
	    	}
			print("biomass add modelcompounds");
	    	$mdlcpd = $self->add("modelcompounds",{
	    		id => $cpdobj->id()."_".$args->{compartment}.$args->{compartmentIndex},
				compound_ref => $cpdobj->_reference(),
				name => $cpdobj->name()."_".$args->{compartment}.$args->{compartmentIndex},
				charge => $cpdobj->defaultCharge(),
				formula => $cpdobj->formula(),
				modelcompartment_ref => "~/modelcompartments/id/".$mdlcmp->id()
			});
		}
	    $bio->adjustBiomassReaction({
	    	coefficient => $args->{coefficient},
			modelcompound => $mdlcpd
	    });
	}
}

=head3 removeModelReaction

Definition:
	Bio::KBase::ObjectAPI::KBaseFBA::FBAModel->removeModelReaction({
		reaction => string,
	});
Description:

=cut
sub removeModelReaction {
    my $self = shift;
    my $args = Bio::KBase::ObjectAPI::utilities::args(["reaction"],{}, @_);
	my $rxnid = $args->{reaction};
	my $mdlrxn = $self->getObject("modelreactions",$rxnid);
	if (!defined($mdlrxn)) {
		Bio::KBase::ObjectAPI::utilities::error("Specified reaction not found:".$rxnid."!");
	}
	$self->remove("modelreactions",$mdlrxn);
}

=head3 adjustModelReaction

Definition:
	Bio::KBase::ObjectAPI::KBaseFBA::FBAModel->adjustModelReaction({
		reaction => string,
		direction => string,
    	gpr => string,
    	enzyme => string,
    	pathway => string,
    	name => string,
    	reference => string
	});
Description:

=cut
sub adjustModelReaction {
    my $self = shift;
    my $args = Bio::KBase::ObjectAPI::utilities::args(["reaction"],{
	    	direction => undef,
	    	gpr => undef,
	    	enzyme => undef,
	    	pathway => undef,
	    	name => undef,
	    	reference => undef,
	    	genetranslation => undef
    }, @_);
	my $rxnid = $args->{reaction};
	my $mdlrxn = $self->getObject("modelreactions",$rxnid);
	if (!defined($mdlrxn)) {
		Bio::KBase::ObjectAPI::utilities::error("Specified reaction not found:".$rxnid."!");
	}
	if (defined($args->{direction})){
		$mdlrxn->direction($args->{direction});
	}
	if (defined($args->{gpr})){
		$mdlrxn->loadGPRFromString($args->{gpr},$args->{genetranslation});
	}
	if (!defined($args->{name}) && !defined($mdlrxn->name()) && length($mdlrxn->name()) == 0)  {
    	$args->{name} = $rxnid;
    }
	if (defined($args->{name}) && $args->{name} ne $rxnid){
		$mdlrxn->name($args->{name});
	}
	if (defined($args->{enzyme})){
		$mdlrxn->enzyme($args->{enzyme});
	}
	if (defined($args->{pathway})){
		$mdlrxn->pathway($args->{pathway});
	}
	if (defined($args->{reference})){
		$mdlrxn->reference($args->{reference});
	}
}

=head3 addModelReaction

Definition:
	Bio::KBase::ObjectAPI::KBaseFBA::FBAModel->addModelReaction({
		reaction => string,
		direction => string,
    	gpr => string,
    	enzyme => string,
    	pathway => string,
    	name => string,
    	reference => string
	});
Description:

=cut

#REFACTOR NEEDED HERE
sub addModelReaction {
    my $self = shift;
    my $args = Bio::KBase::ObjectAPI::utilities::args(["reaction"],{
	    	equation => undef,
	    	direction => undef,
	    	compartment => "c",
	    	compartmentIndex => 0,
	    	gpr => undef,
	    	removeReaction => 0,
	    	addReaction => 0,
	    	compounds => {},
	    	enzyme => undef,
	    	pathway => undef,
	    	name => undef,
	    	reference => undef,
	    	genetranslation => undef
    }, @_);
    my $rootid = $args->{reaction};
	if ($rootid =~ m/(.+)_([a-zA-Z])(\d+)$/) {
		$rootid = $1;
		$args->{compartment} = $2;
    	$args->{compartmentIndex} = $3;
	}
	if ($rootid =~ m/^(.+)\[([a-zA-Z]+)\]$/) {
    	$rootid = $1;
    	$args->{compartment} = lc($2);
    } elsif ($rootid =~ m/^(.+)\[([a-zA-Z]+)(\d+)\]$/) {
    	$rootid = $1;
    	$args->{compartment} = lc($2);
    	$args->{compartmentIndex} = $3;
    }
    #Standardizing and fetching compartment
    if ($args->{compartment} =~ m/^([a-z]+)(\d+)$/ || $args->{compartment} =~ m/(.+)_(\d+)/) {
    	$args->{compartment} = $1;
    	$args->{compartmentIndex} = $2;
    }
    my $cmp = $self->template()->searchForCompartment($args->{compartment});
    if (!defined($cmp)) {
    	$cmp = $self->template()->biochemistry()->searchForCompartment($args->{compartment});
    	if (!defined($cmp)) {
    		Bio::KBase::ObjectAPI::utilities::error("Unrecognized compartment ".$args->{compartment}." in reaction: ".$args->{reaction});
    	}
    }
    $args->{compartment} = $cmp->id();
    my $eq;
    if (defined($args->{equation})) {
    	$eq = $args->{equation};
    	if ($eq =~ m/\[([a-zA-Z])\]\s*:\s*(.+)/) {
    		$args->{compartment} = lc($1);
    		$eq = $2;
    	}
    }
    my $fullid = $rootid."_".$args->{compartment}.$args->{compartmentIndex};
    #Checking if a reaction with the same ID is already in the model
    if (defined($self->getObject("modelreactions",$fullid))) {
    	Bio::KBase::ObjectAPI::utilities::error("Reaction with specified ID ".$rootid." already in model. Remove reaction before attempting to add again!");
    }

    #Fetching or adding model compartment
    my $mdlcmp = $self->addCompartmentToModel({compartment => $cmp,pH => 7,potential => 0,compartmentIndex => $args->{compartmentIndex}});
	#Finding reaction reference
	my $reference = $self->template()->_reference()."/reactions/id/rxn00000_c";
	my $coefhash = {};
	my $rxnobj = $self->template()->searchForReaction($rootid,$cmp->id());
	if (defined($rxnobj)){
		$reference = $rxnobj->_reference();
		my $rgts = $rxnobj->templateReactionReagents();
		my $cmpchange = 0;
		for (my $i=0; $i < @{$rgts}; $i++) {
			if ($rgts->[$i]->templatecompcompound()->templatecompartment()->id() ne "c") {
				$cmpchange = 1;
				last;
			}
		}
		for (my $i=0; $i < @{$rgts}; $i++) {
			my $rgt = $rgts->[$i];
			my $rgtcmp = $mdlcmp;
			if ($cmpchange == 1) {
				if ($rgt->templatecompcompound()->templatecompartment()->id() eq "e") {
					$rgtcmp = $self->addCompartmentToModel({compartment => $rgt->templatecompcompound()->templatecompartment(),pH => 7,potential => 0,compartmentIndex => 0});
				} else {
					$rgtcmp = $self->addCompartmentToModel({compartment => $rgt->templatecompcompound()->templatecompartment(),pH => 7,potential => 0,compartmentIndex => $args->{compartmentIndex}});
				}
			}
			my $coefficient = $rgt->coefficient();
			my $mdlcpd = $self->addCompoundToModel({
				compound => $rgt->templatecompcompound()->templatecompound(),
				modelCompartment => $rgtcmp,
			});
			$coefhash->{"~/modelcompounds/id/".$mdlcpd->id()} = $coefficient;
		}
	} elsif(!defined($eq)) {
		Bio::KBase::ObjectAPI::utilities::error("Specified reaction ".$rootid." not found and no equation provided!");
	}
	#Adding reaction
	my $mdlrxn = $self->add("modelreactions",{
		id => $fullid,
		reaction_ref => $reference,
		direction => $args->{direction},
		protons => 0,
		modelcompartment_ref => "~/modelcompartments/id/".$mdlcmp->id(),
		probability => 0,
		modelReactionReagents => [],
		modelReactionProteins => []
	});
	#Setting reagents from database reaction or equation
	if (!defined($eq)) {
		foreach my $rgt (keys(%{$coefhash})) {
			$mdlrxn->addReagentToReaction({
				coefficient => $coefhash->{$rgt},
				modelcompound_ref => $rgt
			});
		}
	} else {
		$self->LoadExternalReactionEquation({reaction => $mdlrxn,equation => $eq,compounds => $args->{compounds}});
		if ($mdlrxn->id() =~ m/rxn\d+/) {
			$mdlrxn->addAlias($fullid,"id");
		}
	}
	#Adjusting model reaction
	$self->adjustModelReaction({
		reaction => $mdlrxn->id(),
	    	gpr => $args->{gpr},
	    	enzyme => $args->{enzyme},
	    	pathway => $args->{pathway},
	    	reference => $args->{reference},
	    	genetranslation => $args->{genetranslation}
	});
	return $mdlrxn;
}

#REFACTOR NEEDED HERE
sub LoadExternalReactionEquation {
	my $self = shift;
    my $args = Bio::KBase::ObjectAPI::utilities::args(["equation","compounds"],{
    	biomass => undef,
    	reaction => undef
    }, @_);
	$args->{equation} =~ s/\s*\<*[-=]+\>\s*/ = /g;
	$args->{equation} =~ s/\s*\<[-=]+\s*/ = /g;
    $args->{equation} =~ s/\s*\+\s*/ + /g;
    #print "Equation:".$args->{equation}."\n";
    my $array = [];
    if ($args->{equation} =~ m/^(.*)\s=\s(.*)$/) {
    	$array->[0] = $1;
    	$array->[1] = $2;
    } else {
		Bio::KBase::ObjectAPI::utilities::error("No equal sign in ".$args->{equation}."!");
	}
    #print "Reference:".$bio->_reference()."\n";
    my $compoundhash = {};
    for (my $i=0; $i < @{$array}; $i++) {
    	if (length($array->[$i]) > 0) {
	    	my $compounds = [split(/\s\+\s/,$array->[$i])];
	    	foreach my $cpd (@{$compounds}) {
	    		$cpd  =~ s/^\s+//;
	    		$cpd  =~ s/\s+$//;
	    		my $coef = 1;
	    		my $compartment = "c";
	    		if (defined($args->{reaction})) {
	    			$compartment = $args->{reaction}->modelcompartment()->compartment()->id();
	    		}
	    		my $index = 0;
	    		if ($cpd =~ m/^\(*(\d+\.*\d*[eE]*-*\d*)\)*\s+(.+)/) {
	    			$coef = $1;
	    			$cpd = $2;
	    		}
				if ($cpd =~ m/^(.+)\[([a-z]\d*)\]$/) {
	    			$cpd = $1;
	    			$compartment = $2;
	    		}
				if ($cpd =~m/(.+)_([a-z]\d*)$/) {
	    			$cpd = $1;
	    			$compartment = $2;
	    		}
				if (defined($args->{compounds}->{$cpd}->[5])) {
	    			$compartment = $args->{compounds}->{$cpd}->[5];
	    		}
				if ($compartment =~ m/([a-z])(\d+)/) {
	    			$index = $2;
	    			$compartment = $1;
	    		}
	    		if ($i == 0) {
	    			$coef = -1*$coef;
	    		}
	    		my $origid = $cpd."_".$compartment.$index;
	    		$cpd =~ s/\+/PLUS/g;
	    		$cpd =~ s/[\W_]//g;
	    		my $cpdobj;
			my $inchikey = "";
			my $smiles = "";

			my $compound_rec = $args->{compounds}->{$origid};
			if (!defined $compound_rec && $origid !~ m/^cpd\d+_[a-z]\d+$/){
				Bio::KBase::ObjectAPI::utilities::error("Undefined compound used as reactant: $origid");
			}
			#if compoud has a parsed name
	    		if (defined($compound_rec->[3])) {
					# at the moment smiles and inchi always come from source, never templates
					if (defined($compound_rec->[-1])) {
						$inchikey = $compound_rec->[-1];
					}
					if (defined($compound_rec->[-2])) {
						$smiles = $compound_rec->[-2];
					}
	    			my $name = $compound_rec->[3];
	    			if ($name =~ m/^(.+)\[([a-z])\]$/) {
	    				$compartment = $2;
	    				$name = $1;
	    			}
	    			$cpdobj = $self->template()->searchForCompound($name,1);
	    			if (!defined($cpdobj) && defined($compound_rec->[4])) {
	    				my $aliases = [split(/\|/,$compound_rec->[4])];
	    				foreach my $alias (@{$aliases}) {
	    					if ($alias =~ m/^(.+):(.+)/) {
	    						$alias = $2;
	    					}
	    					$cpdobj = $self->template()->searchForCompound($alias,1);
	    					if (defined($cpdobj)) {
	    						last;
	    					}
	    				}
	    			}
	    			if (!defined($cpdobj)) {
	    				$cpdobj = $self->template()->searchForCompound($cpd,1);
	    			}
	    		} else {
	    			$cpdobj = $self->template()->searchForCompound($cpd,1);
	    		}
	    		my $mdlcmp = $self->getObject("modelcompartments",$compartment.$index);
	    		if (!defined($mdlcmp)) {
					print("New compartment: $compartment$index\n");
	    			$mdlcmp = $self->add("modelcompartments",{
	    				id => $compartment.$index,
						compartment_ref => "~/template/compartments/id/".$compartment,
						compartmentIndex => $index,
						label => $compartment.$index,
						pH => 7,
						potential => 0,
	    			});
	    		}
	    		my $mdlcpd;
	    		if (defined($cpdobj)) {
	    			$mdlcpd = $self->searchForCompound($cpdobj->id()."_".$compartment.$index);
	    			my $newcpd = 1;
	    			my $newcpdid = $cpdobj->id();
	    			my $formula = $cpdobj->formula();
	    			if (defined($compound_rec->[2])) {
	    				$formula = $compound_rec->[2];
	    			} else {
	    				$formula = $cpdobj->formula();
	    			}
	    			my $charge;
	    			if (defined($compound_rec->[1])) {
	    				$charge = $compound_rec->[1];
	    			} else {
	    				$charge = $cpdobj->defaultCharge();
	    			}
	    			my $name = $cpdobj->name();
	    			my $reference = $cpdobj->_reference();
	    			if (defined($mdlcpd)) {
	    				$newcpd = 0;
	    			}
	    			if ($newcpd == 1) {
	    				$mdlcpd = $self->add("modelcompounds",{
	    					id => $newcpdid."_".$compartment.$index,
							compound_ref => $reference,
							name => $name."_".$compartment.$index,
							charge => $charge,
							formula => $formula,
							inchikey => $inchikey,
							smiles => $smiles,
							modelcompartment_ref => "~/modelcompartments/id/".$mdlcmp->id(),
							aliases => ["mdlid:".$cpd]
	    				});
	    			}
	    		} else {
	    			$mdlcpd = $self->searchForCompound($cpd."_".$compartment.$index);
	    			if (!defined($mdlcpd)) {
	    				if (!defined($compound_rec)) {
	    					Bio::KBase::utilities::log("Ill defined compound:".$cpd."!");
	    					$cpd =~ s/[^\w]/_/g;
	    					$mdlcpd = $self->searchForCompound($cpd."_".$compartment.$index);
	    					#Bio::KBase::ObjectAPI::utilities::error("Ill defined compound:".$cpd."!");
	    				}
	    				my $newcpd = 1;
		    			if (defined($mdlcpd)) {
		    				$newcpd = 0;
		    				my $aliases = $mdlcpd->aliases();
		    				foreach my $alias (@{$aliases}) {
		    					if ($alias =~ m/^mdlid:(.+)/) {
		    						if ($1 ne $cpd) {
		    							$newcpd = 1;
		    						}
		    					}
		    				}
		    			}
		    			my $formula = "";
		    			if (defined($compound_rec->[2])) {
		    				$formula = $compound_rec->[2];
		    			}
		    			my $charge = 0;
		    			if (defined($compound_rec->[1])) {
		    				$charge = $compound_rec->[1];
		    			}
		    			if ($newcpd == 1) {
							print("new custom compound: $origid\n");
	    					$mdlcpd = $self->add("modelcompounds",{
		    					id => $cpd."_".$compartment.$index,
								compound_ref => $self->template()->_reference()."/compounds/id/cpd00000",
								name => $cpd."_".$compartment.$index,
								charge => $charge,
								formula => $formula,
								inchikey => $inchikey,
								smiles => $smiles,
								modelcompartment_ref => "~/modelcompartments/id/".$mdlcmp->id(),
		    					aliases => ["mdlid:".$cpd]
		    				});
	    				}
	    			}
	    		}
	    		if (!defined($compoundhash->{$mdlcpd->id()})) {
	    			$compoundhash->{$mdlcpd->id()} = 0;
	    		}
	    		$compoundhash->{$mdlcpd->id()} += $coef;
	    	}
    	}
    }
    if (defined($args->{biomass})) {
    	$args->{biomass}->ImportExternalEquation({reagents => $compoundhash});
    } elsif (defined($args->{reaction})) {
    	$args->{reaction}->ImportExternalEquation({reagents => $compoundhash});
    } else {
    	Bio::KBase::ObjectAPI::utilities::error("Must call this function with either reaction or biomass selected!");
    }
}

=head3 labelBiomassCompounds

Definition:
	void Bio::KBase::ObjectAPI::KBaseFBA::FBAModel->labelBiomassCompounds();
Description:
	Labels all model compounds indicating whether or not they are biomass components

=cut

sub labelBiomassCompounds {
	my $self = shift;
	for (my $i=0; $i < @{$self->modelcompounds()}; $i++) {
		my $cpd = $self->modelcompounds()->[$i];
		$cpd->isBiomassCompound(0);
	}
	for (my $i=0; $i < @{$self->biomasses()}; $i++) {
		my $bio = $self->biomasses()->[$i];
		for (my $j=0; $j < @{$bio->biomasscompounds()}; $j++) {
			my $biocpd = $bio->biomasscompounds()->[$j];
			$biocpd->modelcompound()->isBiomassCompound(1);
		}
	}
}

=head3 printSBML

Definition:
	void Bio::KBase::ObjectAPI::KBaseFBA::FBAModel->printSBML();
Description:
	Prints the model in SBML format

=cut

sub printSBML {
    my $self = shift;
	my $args = Bio::KBase::ObjectAPI::utilities::args([], {file => 0,path => undef}, @_);
	# convert ids to SIds
    my $idToSId = sub {
        my $id = shift @_;
        my $cpy = $id;
        # SIds must begin with a letter
        $cpy =~ s/^([^a-zA-Z])/A_$1/;
        # SIDs must only contain letters numbers or '_'
        $cpy =~ s/[^a-zA-Z0-9_]/_/g;
        return $cpy;
    };
	#Printing header to SBML file
	my $ModelName = $idToSId->($self->id());
	my $output;
	push(@{$output},'<?xml version="1.0" encoding="UTF-8"?>');
	push(@{$output},'<sbml xmlns="http://www.sbml.org/sbml/level2" level="2" version="1" xmlns:html="http://www.w3.org/1999/xhtml">');
	my $name = $self->name()." SEED model";
	$name =~ s/[\s\.]/_/g;
	push(@{$output},'<model id="'.$ModelName.'" name="'.$name.'">');

	#Printing the unit data
	push(@{$output},"<listOfUnitDefinitions>");
	push(@{$output},"\t<unitDefinition id=\"mmol_per_gDW_per_hr\">");
	push(@{$output},"\t\t<listOfUnits>");
	push(@{$output},"\t\t\t<unit kind=\"mole\" scale=\"-3\"/>");
	push(@{$output},"\t\t\t<unit kind=\"gram\" exponent=\"-1\"/>");
	push(@{$output},"\t\t\t<unit kind=\"second\" multiplier=\"3600\" scale=\"0\" exponent=\"-1\"/>");
	push(@{$output},"\t\t</listOfUnits>");
	push(@{$output},"\t</unitDefinition>");
	push(@{$output},"</listOfUnitDefinitions>");

	#Printing compartments for SBML file
	push(@{$output},'<listOfCompartments>');
	for (my $i=0; $i < @{$self->modelcompartments()}; $i++) {
		my $cmp = $self->modelcompartments()->[$i];
    	push(@{$output},'<compartment '.$self->CleanNames("id",$cmp->id()).' '.$self->CleanNames("name",$cmp->label()).' />');
    }
	push(@{$output},'</listOfCompartments>');
	#Printing the list of metabolites involved in the model
	push(@{$output},'<listOfSpecies>');
	for (my $i=0; $i < @{$self->modelcompounds()}; $i++) {
		my $cpd = $self->modelcompounds()->[$i];
		push(@{$output},'<species '.$self->CleanNames("id","M_".$cpd->id()).' '.$self->CleanNames("name",$cpd->name()).' compartment="'.$cpd->modelCompartmentLabel().'" charge="'.$cpd->charge().'" boundaryCondition="false"/>');
		if ($cpd->msid() eq "cpd11416" || $cpd->msid() eq "cpd15302" || $cpd->msid() eq "cpd08636" || $cpd->msid() eq "cpd02701") {
			push(@{$output},'<species '.$self->CleanNames("id","M_".$cpd->id(), 1).' '.$self->CleanNames("name",$cpd->name()."_b").' compartment="'.$cpd->modelCompartmentLabel().'" charge="'.$cpd->charge().'" boundaryCondition="true"/>');
		}
	}
	for (my $i=0; $i < @{$self->modelcompounds()}; $i++) {
		my $cpd = $self->modelcompounds()->[$i];
		if ($cpd->modelCompartmentLabel() =~ m/^e/) {
			push(@{$output},'<species '.$self->CleanNames("id","M_".$cpd->id(), 1).' '.$self->CleanNames("name",$cpd->name()."_b").' compartment="'.$cpd->modelCompartmentLabel().'" charge="'.$cpd->charge().'" boundaryCondition="true"/>');
		}
	}
	push(@{$output},'</listOfSpecies>');
	push(@{$output},'<listOfReactions>');
	my $mdlrxns = $self->modelreactions();
	for (my $i=0; $i < @{$mdlrxns}; $i++) {
		my $rxn = $mdlrxns->[$i];
		my $reversibility = "true";
		my $lb = -1000;
		if ($rxn->direction() ne "=") {
			$lb = 0;
			$reversibility = "false";
		}
		push(@{$output},'<reaction '.$self->CleanNames("id","R_".$rxn->id()).' '.$self->CleanNames("name",$rxn->name()).' '.$self->CleanNames("reversible",$reversibility).'>');
		push(@{$output},"<notes>");
		my $ec = $rxn->enzyme();
		my $keggID = $rxn->kegg();
		my $GeneAssociation = $rxn->gprString;
		my $ProteinAssociation = $rxn->gprString;
		push(@{$output},"<html:p>GENE_ASSOCIATION:".$GeneAssociation."</html:p>");
		push(@{$output},"<html:p>PROTEIN_ASSOCIATION:".$ProteinAssociation."</html:p>");
		if (defined($keggID)) {
			push(@{$output},"<html:p>KEGG_RID:".$keggID."</html:p>");
		}
		if (defined($ec)) {
			push(@{$output},"<html:p>PROTEIN_CLASS:".$ec."</html:p>");
		}
		push(@{$output},"</notes>");
		my $firstreact = 1;
		my $firstprod = 1;
		my $prodoutput = [];
		my $rgts = $rxn->modelReactionReagents();
		my $sign = 1;
		if ($rxn->direction() eq "<") {
			$sign = -1;
		}
		for (my $j=0; $j < @{$rgts}; $j++) {
			my $rgt = $rgts->[$j];
			my $rgtid = $rgt->modelcompound_ref();
			$rgtid =~ s/.+\///;
			if ($sign*$rgt->coefficient() < 0) {
				if ($firstreact == 1) {
					$firstreact = 0;
					push(@{$output},"<listOfReactants>");
				}
				push(@{$output},'<speciesReference '.$self->CleanNames("species","M_".$rgtid).' stoichiometry="'.-1*$sign*$rgt->coefficient().'"/>');
			} else {
				if ($firstprod == 1) {
					$firstprod = 0;
					push(@{$prodoutput},"<listOfProducts>");
				}
				push(@{$prodoutput},'<speciesReference '.$self->CleanNames("species","M_".$rgtid).' stoichiometry="'.$sign*$rgt->coefficient().'"/>');
			}
		}
		if ($firstreact != 1) {
			push(@{$output},"</listOfReactants>");
		}
		if ($firstprod != 1) {
			push(@{$prodoutput},"</listOfProducts>");
		}
		push(@{$output},@{$prodoutput});
		push(@{$output},"<kineticLaw>");
		push(@{$output},"\t<math xmlns=\"http://www.w3.org/1998/Math/MathML\">");
		push(@{$output},"\t\t\t<ci> FLUX_VALUE </ci>");
		push(@{$output},"\t</math>");
		push(@{$output},"\t<listOfParameters>");
		push(@{$output},"\t\t<parameter id=\"LOWER_BOUND\" value=\"".$lb."\" name=\"mmol_per_gDW_per_hr\"/>");
		push(@{$output},"\t\t<parameter id=\"UPPER_BOUND\" value=\"1000\" name=\"mmol_per_gDW_per_hr\"/>");
		push(@{$output},"\t\t<parameter id=\"OBJECTIVE_COEFFICIENT\" value=\"0\"/>");
		push(@{$output},"\t\t<parameter id=\"FLUX_VALUE\" value=\"0.0\" name=\"mmol_per_gDW_per_hr\"/>");
		push(@{$output},"\t</listOfParameters>");
		push(@{$output},"</kineticLaw>");
		push(@{$output},'</reaction>');
	}
	my $bios = $self->biomasses();
	for (my $i=0; $i < @{$bios}; $i++) {
		my $rxn = $bios->[$i];
		my $obj = 0;
		if ($i==0) {
			$obj = 1;
		}
		my $reversibility = "false";
		push(@{$output},'<reaction '.$self->CleanNames("id",$bios->[$i]->id()).' '.$self->CleanNames("name",$rxn->name()).' '.$self->CleanNames("reversible",$reversibility).'>');
		push(@{$output},"<notes>");
		push(@{$output},"<html:p>GENE_ASSOCIATION: </html:p>");
		push(@{$output},"<html:p>PROTEIN_ASSOCIATION: </html:p>");
		push(@{$output},"<html:p>SUBSYSTEM: </html:p>");
		push(@{$output},"<html:p>PROTEIN_CLASS: </html:p>");
		push(@{$output},"</notes>");
		my $firstreact = 1;
		my $firstprod = 1;
		my $prodoutput = [];
		my $biocpds = $rxn->biomasscompounds();
		for (my $j=0; $j < @{$biocpds}; $j++) {
			my $rgt = $biocpds->[$j];
			my $rgtid = $rgt->modelcompound_ref();
			$rgtid =~ s/.+\///;
			if ($rgt->coefficient() < 0) {
				if ($firstreact == 1) {
					$firstreact = 0;
					push(@{$output},"<listOfReactants>");
				}
				push(@{$output},'<speciesReference '.$self->CleanNames("species","M_".$rgtid).' stoichiometry="'.-1*$rgt->coefficient().'"/>');
			} else {
				if ($firstprod == 1) {
					$firstprod = 0;
					push(@{$prodoutput},"<listOfProducts>");
				}
				push(@{$prodoutput},'<speciesReference '.$self->CleanNames("species","M_".$rgtid).' stoichiometry="'.$rgt->coefficient().'"/>');
			}
		}
		if ($firstreact != 1) {
			push(@{$output},"</listOfReactants>");
		}
		if ($firstprod != 1) {
			push(@{$prodoutput},"</listOfProducts>");
		}
		push(@{$output},@{$prodoutput});
		push(@{$output},"<kineticLaw>");
		push(@{$output},"\t<math xmlns=\"http://www.w3.org/1998/Math/MathML\">");
		push(@{$output},"\t\t\t<ci> FLUX_VALUE </ci>");
		push(@{$output},"\t</math>");
		push(@{$output},"\t<listOfParameters>");
		push(@{$output},"\t\t<parameter id=\"LOWER_BOUND\" value=\"0.0\" name=\"mmol_per_gDW_per_hr\"/>");
		push(@{$output},"\t\t<parameter id=\"UPPER_BOUND\" value=\"1000\" name=\"mmol_per_gDW_per_hr\"/>");
		push(@{$output},"\t\t<parameter id=\"OBJECTIVE_COEFFICIENT\" value=\"".$obj."\"/>");
		push(@{$output},"\t\t<parameter id=\"FLUX_VALUE\" value=\"0.0\" name=\"mmol_per_gDW_per_hr\"/>");
		push(@{$output},"\t</listOfParameters>");
		push(@{$output},"</kineticLaw>");
		push(@{$output},'</reaction>');
	}
	my $cpds = $self->modelcompounds();
	for (my $i=0; $i < @{$cpds}; $i++) {
		my $cpd = $cpds->[$i];
		my $lb = -1000;
		my $ub = 1000;
		if ($cpd->modelCompartmentLabel() =~ m/^e/ || $cpd->msid() eq "cpd08636" || $cpd->msid() eq "cpd11416" || $cpd->msid() eq "cpd15302" || $cpd->msid() eq "cpd02701") {
			push(@{$output},'<reaction '.$self->CleanNames("id",'EX_'.$cpd->id()).' '.$self->CleanNames("name",'EX_'.$cpd->name()).' reversible="true">');
			push(@{$output},"\t".'<notes>');
			push(@{$output},"\t\t".'<html:p>GENE_ASSOCIATION: </html:p>');
			push(@{$output},"\t\t".'<html:p>PROTEIN_ASSOCIATION: </html:p>');
			push(@{$output},"\t\t".'<html:p>PROTEIN_CLASS: </html:p>');
			push(@{$output},"\t".'</notes>');
			push(@{$output},"\t".'<listOfReactants>');
			push(@{$output},"\t\t".'<speciesReference '.$self->CleanNames("species","M_".$cpd->id()).' stoichiometry="1.000000"/>');
			push(@{$output},"\t".'</listOfReactants>');
			push(@{$output},"\t".'<listOfProducts>');
			push(@{$output},"\t\t".'<speciesReference '.$self->CleanNames("species","M_".$cpd->id(), 1).' stoichiometry="1.000000"/>');
			push(@{$output},"\t".'</listOfProducts>');
			push(@{$output},"\t".'<kineticLaw>');
			push(@{$output},"\t\t".'<math xmlns="http://www.w3.org/1998/Math/MathML">');
			push(@{$output},"\t\t\t\t".'<ci> FLUX_VALUE </ci>');
			push(@{$output},"\t\t".'</math>');
			push(@{$output},"\t\t".'<listOfParameters>');
			push(@{$output},"\t\t\t".'<parameter id="LOWER_BOUND" value="'.$lb.'" units="mmol_per_gDW_per_hr"/>');
			push(@{$output},"\t\t\t".'<parameter id="UPPER_BOUND" value="'.$ub.'" units="mmol_per_gDW_per_hr"/>');
			push(@{$output},"\t\t\t".'<parameter id="OBJECTIVE_COEFFICIENT" value="0"/>');
			push(@{$output},"\t\t\t".'<parameter id="FLUX_VALUE" value="0.000000" units="mmol_per_gDW_per_hr"/>');
			push(@{$output},"\t\t".'</listOfParameters>');
			push(@{$output},"\t".'</kineticLaw>');
			push(@{$output},'</reaction>');
		}
	}
	#Closing out the file
	push(@{$output},'</listOfReactions>');
	push(@{$output},'</model>');
	push(@{$output},'</sbml>');
	if ($args->{file} == 1) {
		Bio::KBase::ObjectAPI::utilities::PRINTFILE($args->{path}."/".$self->id().".sbml",$output);
		return [$args->{path}."/".$self->id().".sbml"]
	}
	return join("\n",@{$output});
}

sub printTSV {
	my $self = shift;
	my $args = Bio::KBase::ObjectAPI::utilities::args([], {file => 0,path => undef,fulldb => 0}, @_);
	my $output = {
		compounds_table => ["id\tname\tformula\tcharge\tinchikey\tsmiles\tdeltag\tkegg id\tms id"],
		reactions_table => ["id\tdirection\tcompartment\tgpr\tname\tenzyme\tdeltag\treference\tequation\tdefinition\tms id\tbigg id\tkegg id\tkegg pathways\tmetacyc pathways"]
	};
	if ($args->{fulldb} == 1) {
		$output->{compounds_table}->[0] .= "\tin model";
		$output->{reactions_table}->[0] .= "\tin model";
	}
	my $kegghash = Bio::KBase::utilities::kegg_hash();
	my $cpdhash = Bio::KBase::utilities::compound_hash();
	my $rxnhash = Bio::KBase::utilities::reaction_hash();
	my $compounds = $self->modelcompounds();
	my $cpd_id_hash = {};
	my $rxn_id_hash = {};
	for (my $i=0; $i < @{$compounds}; $i++) {
		local $SIG{__WARN__} = sub { };
		# The follow line works but throws a shit-ton of warnings.
		my $cpddata;
		my $msid = "";
		$cpd_id_hash->{$compounds->[$i]->id()} = 1;
		if ($compounds->[$i]->id() =~ m/(cpd\d+)/ || $compounds->[$i]->compound_ref() =~ m/(cpd\d+)/) {
			$msid = $1;
			if ($msid ne "" && $msid ne "cpd00000" && defined($cpdhash->{$msid})) {
				$cpddata = $cpdhash->{$msid};
			}
		}
		my $name = $compounds->[$i]->id();
		if (defined($compounds->[$i]->name()) && length($compounds->[$i]->name()) > 0) {
			$name = $compounds->[$i]->name();
		} elsif (defined($cpddata)) {
			$name = $cpddata->{name};
		}
		my $formula = "";
		if (defined($compounds->[$i]->formula()) && length($compounds->[$i]->formula()) > 0) {
			$formula = $compounds->[$i]->formula();
		} elsif (defined($cpddata)) {
			$formula = $cpddata->{formula};
		}
		my $charge = "";
		if (defined($compounds->[$i]->charge()) && length($compounds->[$i]->charge()) > 0) {
			$charge = $compounds->[$i]->charge();
		} elsif (defined($cpddata)) {
			$charge = $cpddata->{charge};
		}
		my $inchikey = "";
		if (defined($compounds->[$i]->inchikey()) && length($compounds->[$i]->inchikey()) > 0) {
			$inchikey = $compounds->[$i]->inchikey();
		} elsif (defined($cpddata) && defined($cpddata->{inchikey})) {
			$inchikey = $cpddata->{inchikey};
		}
		my $smiles = "";
		if (defined($compounds->[$i]->smiles()) && length($compounds->[$i]->smiles()) > 0) {
			$smiles = $compounds->[$i]->smiles();
		} elsif (defined($cpddata) && defined($cpddata->{smiles})) {
			$smiles = $cpddata->{smiles};
		}
		my $deltag = "";
		if (defined($cpddata) && defined($cpddata->{deltag}) && $cpddata->{deltag} != 10000000) {
			$deltag = $cpddata->{deltag};
		}
		my $keggid = "";
		if (defined($cpddata) && defined($cpddata->{kegg_aliases}->[0])) {
			$keggid = $cpddata->{kegg_aliases}->[0];
		}
		my $line = $compounds->[$i]->id()."\t".$name."\t".$formula."\t".$charge."\t".$inchikey."\t".$smiles."\t".$deltag."\t".$keggid."\t".$msid;
		if ($args->{fulldb} == 1) {
			$line .= "\t1";
		}
		push(@{$output->{compounds_table}},$line);
	}
	my $reactions = $self->modelreactions();
	for (my $i=0; $i < @{$reactions}; $i++) {
		my $pathway = "";
		if (defined($reactions->[$i]->pathway())) {
			$pathway = $reactions->[$i]->pathway();
		}
		my $reference = "";
		if (defined($reactions->[$i]->reference())) {
			$reference = $reactions->[$i]->reference();
		}
		my $equation = $reactions->[$i]->equation();
		$equation =~ s/\)/) /g;
		my $definition = $reactions->[$i]->definition();
		$definition =~ s/\)/) /g;
		my $rxndata;
		my $msid = "";
		$rxn_id_hash->{$reactions->[$i]->id()} = 1;
		if ($reactions->[$i]->id() =~ m/(rxn\d+)/ || $reactions->[$i]->reaction_ref() =~ m/(rxn\d+)/) {
			$msid = $1;
			if ($msid ne "" && $msid ne "rxn00000" && defined($rxnhash->{$msid})) {
				$rxndata = $rxnhash->{$msid};
			}
		}
		my $deltag = "";
		if (defined($rxndata) && defined($rxndata->{deltag}) && $rxndata->{deltag} != 10000000) {
			$deltag = $rxndata->{deltag};
		}
		my $ec = "";
		if (defined($rxndata) && defined($rxndata->{ec_numbers}) && defined($rxndata->{ec_numbers}->[0])) {
			$ec = join("|", @{$rxndata->{ec_numbers}});
		}
		my $biggid = "";
		if (defined($rxndata) && defined($rxndata->{bigg_aliases}) && defined($rxndata->{bigg_aliases}->[0])) {
			$biggid = $rxndata->{bigg_aliases}->[0];
		}
		my $keggid = "";
		if (defined($rxndata) && defined($rxndata->{kegg_aliases}) && defined($rxndata->{kegg_aliases}->[0])) {
			$keggid = $rxndata->{kegg_aliases}->[0];
		}

		my $metapath = "";
		if (defined($rxndata) && defined($rxndata->{metacyc_pathways}) && defined($rxndata->{metacyc_pathways}->[0])) {
			for (my $j=0; $j < @{$rxndata->{metacyc_pathways}}; $j++) {
				if ($rxndata->{metacyc_pathways}->[$j] !~ /PWY-\d+/) {
					if (length($metapath) > 0) {
						$metapath .= "|";
					}
					$metapath .= $rxndata->{metacyc_pathways}->[$j];
				}
			}
		}
		my $keggpath = "";
		if (defined($rxndata) && defined($rxndata->{kegg_pathways}) && defined($rxndata->{kegg_pathways}->[0])) {
			for (my $j=0; $j < @{$rxndata->{kegg_pathways}}; $j++) {
				if (defined($kegghash->{$rxndata->{kegg_pathways}->[$j]})) {
					if (length($keggpath) > 0) {
						$keggpath .= "|";
					}
					$keggpath .= $kegghash->{$rxndata->{kegg_pathways}->[$j]};
				}
			}
		}
		my $line = $reactions->[$i]->id()."\t".$reactions->[$i]->direction()."\t".$reactions->[$i]->modelcompartment()->label()."\t".$reactions->[$i]->gprString()."\t".$reactions->[$i]->name()."\t".$ec."\t".$deltag."\t".$reference."\t".$equation."\t".$definition."\t".$msid."\t".$biggid."\t".$keggid."\t".$keggpath."\t".$metapath;
		if ($args->{fulldb} == 1) {
			$line .= "\t1";
		}
		push(@{$output->{reactions_table}},$line);
	}
	if ($args->{fulldb} == 1) {
		$self->template()->printTSV({
			file => 0,
			append_to => $output,
			compound_filter => $cpd_id_hash,
			reaction_filter => $rxn_id_hash
		});
	}
	$reactions = $self->biomasses();
	for (my $i=0; $i < @{$reactions}; $i++) {
		my $equation = $reactions->[$i]->equation();
		$equation =~ s/\)/) /g;
		my $definition = $reactions->[$i]->definition();
		$definition =~ s/\)/) /g;
		push(@{$output->{reactions_table}},$reactions->[$i]->id()."\t=>\tc0\t\t".$reactions->[$i]->name()."\t\t\t\t".$equation."\t".$definition);
	}
	if ($args->{file} == 1) {
		Bio::KBase::ObjectAPI::utilities::PRINTFILE($args->{path}."/".$self->id()."-compounds.tsv",$output->{compounds_table});
		Bio::KBase::ObjectAPI::utilities::PRINTFILE($args->{path}."/".$self->id()."-reactions.tsv",$output->{reactions_table});
		return [$args->{path}."/".$self->id()."-compounds.tsv",$args->{path}."/".$self->id()."-reactions.tsv"];
	}
	return $output;
}

sub printExcel {
	my $self = shift;
	my $args = Bio::KBase::ObjectAPI::utilities::args([], {file => 0,path => undef,fulldb => 0}, @_);
	my $output = $self->printTSV({fulldb => $args->{fulldb}});
	require "Spreadsheet/WriteExcel.pm";
	my $wkbk = Spreadsheet::WriteExcel->new($args->{path}."/".$self->id().".xls") or die "can not create workbook: $!";
	my $sheet = $wkbk->add_worksheet("ModelCompounds");
	for (my $i=0; $i < @{$output->{compounds_table}}; $i++) {
		my $row = [split(/\t/,$output->{compounds_table}->[$i])];
		for (my $j=0; $j < @{$row}; $j++) {
			if (defined($row->[$j])) {
				$row->[$j] =~ s/=/-/g;
			}
		}
		$sheet->write_row($i,0,$row);
	}
	$sheet = $wkbk->add_worksheet("ModelReactions");
	for (my $i=0; $i < @{$output->{reactions_table}}; $i++) {
		my $row = [split(/\t/,$output->{reactions_table}->[$i])];
		for (my $j=0; $j < @{$row}; $j++) {
			if (defined($row->[$j])) {
				$row->[$j] =~ s/=/-/g;
			}
		}
		$sheet->write_row($i,0,$row);
	}
	$wkbk->close();
	if ($args->{file} == 0) {
		Bio::KBase::error("Export to excel is only supported as a file output!");
	}
	return [$args->{path}."/".$self->id().".xls"];
}

sub CleanNames {
	my ($self,$name,$value,$boundary) = @_;
	$value =~ s/\+/_plus_/g;
	$value =~ s/[\s:,-]/_/g;
	$value =~ s/\W//g;
	if ($boundary){
		$value =~ s/_[a-z]\d*$//;
		$value .= "_b"
	}
	return $name.'="'.$value.'"';
}

=head3 export

Definition:
	string = Bio::KBase::ObjectAPI::KBaseFBA::FBAModel->export();
Description:
	Exports model data to the specified format.

=cut

sub export {
    my $self = shift;
	my $args = Bio::KBase::ObjectAPI::utilities::args(["format"], {file => 0,path => undef}, @_);
	if (lc($args->{format}) eq "sbml") {
		return $self->printSBML($args);
	} elsif (lc($args->{format}) eq "excel") {
		return $self->printExcel($args);
	} elsif (lc($args->{format}) eq "fullexcel") {
		$args->{fulldb} = 1;
		return $self->printExcel($args);
	} elsif (lc($args->{format}) eq "tsv") {
		return $self->printTSV($args);
	} elsif (lc($args->{format}) eq "fulltsv") {
		$args->{fulldb} = 1;
		return $self->printTSV($args);
	}
	Bio::KBase::ObjectAPI::utilities::error("Unrecognized type for export: ".$args->{format});
}

#***********************************************************************************************************
# ANALYSIS FUNCTIONS:
#***********************************************************************************************************

=head3 deleteGapfillSolution

Definition:
	void Bio::KBase::ObjectAPI::KBaseFBA::FBAModel->deleteGapfillSolution({
		gapfll => string
	});
Description:
	Deletes a gapfilling solution in the model

=cut

sub deleteGapfillSolution {
    my $self = shift;
	my $args = Bio::KBase::ObjectAPI::utilities::args(["gapfill"], {}, @_);
	my $gfmeta = $self->getObject("gapfillings",$args->{gapfill});
	if (!defined($gfmeta)) {
		Bio::KBase::ObjectAPI::utilities::error("Gapfill ".$args->{gapfill}." not found!");
	}
	if ($gfmeta->integrated() == 1) {
		$self->unintegrateGapfillSolution({
			gapfill => $args->{gapfill}
		});
	}
	$self->remove("gapfillings",$gfmeta);
}

=head3 unintegrateGapfillSolution

Definition:
	void Bio::KBase::ObjectAPI::KBaseFBA::FBAModel->unintegrateGapfillSolution({
		solution => Bio::KBase::ObjectAPI::KBaseFBA::Gapfilling*
	});
Description:
	Unintegrates a gapfilling solution in the model

=cut

sub unintegrateGapfillSolution {
    my $self = shift;
	my $args = Bio::KBase::ObjectAPI::utilities::args(["gapfill"], {}, @_);
	Bio::KBase::ObjectAPI::utilities::verbose("Now integrating gapfill solution into model");
	my $gfmeta = $self->getObject("gapfillings",$args->{gapfill});
	if (!defined($gfmeta)) {
		Bio::KBase::ObjectAPI::utilities::error("Gapfill ".$args->{gapfill}." not found!");
	}
	if ($gfmeta->integrated() == 0) {
		Bio::KBase::ObjectAPI::utilities::error("Gapfill ".$args->{gapfill}." not currently integrated!");
	}
	$self->_clearIndex();
	$gfmeta->integrated(0);
	$gfmeta->integrated_solution(-1);
	my $rxns = $self->modelreactions();
	for (my $i=0; $i < @{$rxns}; $i++) {
		my $rxn = $rxns->[$i];
		if (defined($rxn->gapfill_data()->{$gfmeta->id()})) {
			#making sure no other integrated gapfillings operate in the same direction
			my $gfdata = $rxn->gapfill_data()->{$gfmeta->id()};
			my $gfarray = [split(/:/,$gfdata)];
			my $found = 0;
			foreach my $gfid (keys(%{$rxn->gapfill_data()})) {
				if ($gfid ne $gfmeta->id()) {
					my $data = $rxn->gapfill_data()->{$gfid};
					my $array = [split(/:/,$data)];
					if ($array->[1] eq $gfarray->[1]) {
						$found = 1;
						last;
					}
				}
			}
			#deleting entry
			delete $rxn->gapfill_data()->{$gfmeta->id()};
			#removing direction if no other gapfilling was found
			if ($found == 0) {
				if ($rxn->direction() eq $gfarray->[1]) {
					$self->remove("modelreactions",$rxn);
				} elsif ($gfarray->[1] eq ">" && $rxn->direction() eq "=") {
					$rxn->direction("<");
				} elsif ($gfarray->[1] eq "<" && $rxn->direction() eq "=") {
					$rxn->direction(">");
				}
			}
		}
	}
	return $gfmeta;
}

=head3 add_gapfilling

Definition:
	void Bio::KBase::ObjectAPI::KBaseFBA::FBAModel->add_gapfilling({
		object => Bio::KBase::ObjectAPI::KBaseFBA::FBA,
		solution_to_integrate => int
	});
Description:
	Adds a gapfilling object

=cut

sub add_gapfilling {
    my $self = shift;
	my $args = Bio::KBase::ObjectAPI::utilities::args(["object","id"], {solution_to_integrate => undef}, @_);
	Bio::KBase::utilities::log("Integrating gapfill solution into model","stdout");
	#Adding gapfill object to model
	my $gfobj = {
		id => $args->{id},
		gapfill_id => $args->{object}->id(),
		integrated => 0,
		media_ref => $args->{object}->media()->_reference()
	};
	if (defined($args->{solution_to_integrate})) {
		$gfobj->{integrated} = 1;
		$gfobj->{integrated_solution} = $args->{solution_to_integrate};
	}
	$self->add("gapfillings",$gfobj);
	#Integrating biomass removal information into biomass compounds
	my $biomass_removals = $args->{object}->biomassRemovals();
	my $brkeys = [keys(%{$biomass_removals})];
	if (@{$brkeys} > 0) {
		my $tbl = "<h3>Gapfilling was unable to find a solution using the chosen media.</h3>";
		return Bio::KBase::utilities::gapfilling_html_table({message => $tbl,append => 0});
		# Rest is of code block is skipped
		my $biomass = "bio1";
		if (!defined($biomass_removals->{bio1})) {
			$biomass = $brkeys->[0];
		}
		$biomass_removals = $biomass_removals->{$biomass};
		my $bioobj = $self->getObject("biomasses",$biomass);
		for (my $i=0; $i < @{$biomass_removals}; $i++) {
			my $biocpds = $bioobj->biomasscompounds();
			my $selectedcpd;
			for (my $j=0; $j < @{$biocpds}; $j++) {
				if ($biocpds->[$j]->modelcompound()->id() eq $biomass_removals->[$i]) {
					$selectedcpd = $biocpds->[$j];
					last;
				}
			}
			if (defined($args->{solution_to_integrate})) {
				$selectedcpd->gapfill_data()->{$args->{id}} = 1;
				$bioobj->add("removedcompounds",$selectedcpd);
				$bioobj->remove("biomasscompounds",$selectedcpd);
			} else {
				$selectedcpd->gapfill_data()->{$args->{id}} = 0;
			}
		}
	}
	#Integrating reaction addition information into model
	my $solutions = $args->{object}->gapfillingSolutions();
	my $added = 0;
	my $reversed = 0;
	my $gfarray = [];
	for (my $i=0; $i < @{$solutions}; $i++) {
		my $solution = $solutions->[$i];
		my $integrated = 0;
		if (defined($args->{solution_to_integrate}) && $args->{solution_to_integrate} eq $i) {
			$integrated = 1;
		}
		my $rxns = $solution->gapfillingSolutionReactions();
		for (my $j=0; $j < @{$rxns}; $j++) {
			my $rxn = $rxns->[$j];
			my $rxnid = $rxn->reaction()->id();
			my $mdlrxn;
			my $ismdlrxn = 0;
			if ($rxnid =~ m/(.+)_([a-zA-Z]+)(\d+)$/) {
				my $idindex = $3;
				if ($idindex != $rxn->compartmentIndex()) {
					$rxnid = $1."_".$2.$rxn->compartmentIndex();
				}
				$ismdlrxn = 1;
				$mdlrxn = $self->getObject("modelreactions",$rxnid);
			} else {
				$mdlrxn = $self->getObject("modelreactions",$rxnid.$rxn->compartmentIndex());
			}
			if (defined($mdlrxn)) {
				$mdlrxn->gapfill_data()->{$args->{id}}->{$i} = [$rxn->direction(),$integrated,[]];
				if ($rxn->direction() ne $mdlrxn->direction() && $integrated == 1) {
					$reversed++;
					push(@{$gfarray},{obj => $mdlrxn, dir => $rxn->direction(),action => "reversed"});
					$mdlrxn->direction("=");
				}
			} else {
				if ($rxnid =~ m/.+_[a-zA-Z]\d+$/) {
					$ismdlrxn = 1;
					$mdlrxn = $self->getObject("gapfilledcandidates",$rxnid);
				} else {
					$mdlrxn = $self->getObject("gapfilledcandidates",$rxnid.$rxn->compartmentIndex());
				}
				if (defined($mdlrxn)) {
					$mdlrxn->gapfill_data()->{$args->{id}}->{$i} = [$rxn->direction(),$integrated,[]];
					if ($integrated == 1) {
						$added++;
						push(@{$gfarray},{obj => $mdlrxn, dir => $rxn->direction(),action => "added"});
						$self->add("modelreactions",$mdlrxn);
						$mdlrxn->direction() = $rxn->direction();
						$self->removed("gapfilledcandidates",$mdlrxn);
					}
				}
			}
			if (!defined($mdlrxn)) {
				if ($ismdlrxn == 1) {
					if (!defined($self->getObject("modelcompartments",$rxn->compartment()->id().$rxn->compartmentIndex()))) {
						$self->add("modelcompartments",{
							id => $rxn->compartment()->id().$rxn->compartmentIndex(),
							compartment_ref => $rxn->compartment()->_reference(),
							label => $rxn->compartment()->name()."_".$rxn->compartmentIndex(),
							pH => 7,
							compartmentIndex => $rxn->compartmentIndex()
						});
					}
					$mdlrxn = $rxn->reaction()->cloneObject();
					$mdlrxn->parent($rxn->reaction()->parent());
					$mdlrxn->gapfill_data({});
					my $prots = $mdlrxn->modelReactionProteins();
					for (my $m=0; $m < @{$prots}; $m++) {
						$mdlrxn->remove("modelReactionProteins",$prots->[$m]);
					}
					$mdlrxn->direction($rxn->direction());
					my $newrgts = [];
					my $rgts = $mdlrxn->modelReactionReagents();
					for (my $m=0; $m < @{$rgts}; $m++) {
						if ($rgts->[$m]->modelcompound_ref =~ m/\/([^\/]+)_([a-z]+)(\d+)$/) {
							my $cmpid = $2;
							my $mdlcpdid = $1."_".$cmpid.$rxn->compartmentIndex();
							my $mdlcmpdid = $cmpid.$rxn->compartmentIndex();
							my $index = $rxn->compartmentIndex();
							if ($cmpid eq "e") {
								$mdlcpdid = $1."_".$cmpid."0";
								$mdlcmpdid = $cmpid."0";
								$index = 0;
							}
							push(@{$newrgts},{
								modelcompound_ref => "~/modelcompounds/id/".$mdlcpdid,
								coefficient => $rgts->[$m]->coefficient()
							});
							if (!defined($self->getObject("modelcompounds",$mdlcpdid))) {
								if (!defined($self->getObject("modelcompartments",$mdlcmpdid))) {
									$self->add("modelcompartments",{
										id => $mdlcmpdid,
										compartment_ref => "~/template/compartments/id/".$cmpid,
										label => $cmpid."_".$index,
										pH => 7,
										compartmentIndex => $index
									});
								}
								my $name = $rgts->[$m]->modelcompound()->name();
								$name =~ s/_[a-z]+\d+$/_$mdlcmpdid/;
								my $mdlcpd = $self->add("modelcompounds",{
									id => $mdlcpdid,
									compound_ref => $rgts->[$m]->modelcompound()->compound_ref(),
									name => $name,
									aliases => $rgts->[$m]->modelcompound()->aliases(),
									charge => $rgts->[$m]->modelcompound()->charge(),
									maxuptake => $rgts->[$m]->modelcompound()->maxuptake(),
									formula => $rgts->[$m]->modelcompound()->formula(),
									modelcompartment_ref => "~/modelcompartments/id/".$mdlcmpdid,
								});
							}
						}
						$mdlrxn->remove("modelReactionReagents",$rgts->[$m]);
					}
					for (my $m=0; $m < @{$newrgts}; $m++) {
						$mdlrxn->add("modelReactionReagents",$newrgts->[$m]);
					}
					$mdlrxn->parent($self);
					$mdlrxn->gapfill_data()->{$args->{id}}->{$i} = [$rxn->direction(),$integrated,[]];
					if ($integrated == 1) {
						$added++;
						push(@{$gfarray},{obj => $mdlrxn, dir => $rxn->direction(),action => "added"});
						$mdlrxn = $self->add("modelreactions",$mdlrxn);
					} else {
						$mdlrxn = $self->add("gapfilledcandidates",$mdlrxn);
					}
				} else {
					$mdlrxn = $self->addModelReaction({
						reaction => $rxn->reaction()->msid(),
						compartment => $rxn->reaction()->templatecompartment()->id(),
						compartmentIndex => $rxn->compartmentIndex(),
						direction => $rxn->direction()
					});
					$mdlrxn->gapfill_data()->{$args->{id}}->{$i} = [$rxn->direction(),$integrated,[]];
					if ($integrated == 0) {
						$self->add("gapfilledcandidates",$mdlrxn);
						$self->remove("modelreactions",$mdlrxn);
					} else {
						push(@{$gfarray},{obj => $mdlrxn, dir => $rxn->direction(),action => "added"});
						$added++;
					}
				}
			}
		}
	}

	my $tbl = "<p>During gapfilling, ".$added." new reactions were added to the model, while ".$reversed." existing reactions were made reversible.";
	if (@{$gfarray} > 0) {
		$tbl .= " The reactions added and modified during gapfilling are listed below:</p><br>";
		$tbl .= "<table class=\"reporttbl\"><tr><th>Reaction</th><th>Direction</th><th>Equation</th><th>Action</th></tr>";
		foreach my $gfrxn (@{$gfarray}) {
			$tbl .= "<tr><td>".$gfrxn->{obj}->id()."</td><td>".$gfrxn->{dir}."</td><td>".$gfrxn->{obj}->definition()."</td><td>".$gfrxn->{action}."</td></tr>";
		}
		$tbl .= "</table>";
	} else {
		$tbl .= "</p>";
	}
	Bio::KBase::utilities::gapfilling_html_table({message => $tbl,append => 0});
}

=head3 searchForCompound

Definition:
	Bio::KBase::ObjectAPI::KBaseFBA::ModelCompound Bio::KBase::ObjectAPI::KBaseFBA::ModelCompound->searchForCompound(string:id);
Description:
	Search for compound in model

=cut

sub searchForCompound {
    my $self = shift;
    my $id = shift;
    my $compartment = shift;
    my $index = shift;
    if ($id =~ m/^(.+)_([a-z]+)(\d*)$/) {
    	$id = $1;
    	$compartment = $2;
    	$index = $3;
    }
    if ($id =~ m/^(.+)\[([a-z]+)(\d*)]$/) {
    	$id = $1;
    	$compartment = $2;
    	$index = $3;
    }
    if (!defined($compartment)) {
    	$compartment = "c";
    }
    if (!defined($index)) {
    	$index = 0;
    }
    my $mdlcpd = $self->getObject("modelcompounds",$id."_".$compartment.$index);
    if (!defined($mdlcpd)) {
	    my $cpd = $self->template()->searchForCompound($id);
	    if (!defined($cpd)) {
	    	return undef;
	    }
	    my $mdlcmp = $self->queryObject("modelcompartments",{label => $compartment.$index});
	    if (!defined($mdlcmp)) {
	    	return undef;
	    }
	    return $self->queryObject("modelcompounds",{
	    	modelcompartment_ref => $mdlcmp->_reference(),
	    	msid => $cpd->msid()
	    });
    }
    return $mdlcpd;
}

=head3 searchForBiomass

Definition:
	Bio::KBase::ObjectAPI::KBaseFBA::Biomass Bio::KBase::ObjectAPI::KBaseFBA::Biomass->searchForBiomass(string:id);
Description:
	Search for biomass in model

=cut

sub searchForBiomass {
    my $self = shift;
    my $id = shift;
    my $obj = $self->queryObject("biomasses",{id => $id});
    if (!defined($obj)) {
    	$obj = $self->queryObject("biomasses",{name => $id});
    }
    return $obj;
}

=head3 searchForReaction

Definition:
	Bio::KBase::ObjectAPI::KBaseFBA::Biomass Bio::KBase::ObjectAPI::KBaseFBA::Biomass->searchForReaction(string:id);
Description:
	Search for reaction in model

=cut

sub searchForReaction {
    my $self = shift;
    my $id = shift;
    my $compartment = shift;
    my $index = shift;
    if ($id =~ m/^(.+)\[([a-z]+)(\d*)]$/) {
    	$id = $1;
    	$compartment = $2;
    	$index = $3;
    } elsif ($id =~ m/^(.+)_([a-z]+)(\d+)$/) {
    	$id = $1;
    	$compartment = $2;
    	$index = $3;
    }
    if (!defined($compartment)) {
    	$compartment = "c";
    }
    if (!defined($index)) {
    	$index = 0;
    }
    my $mdlrxn = $self->getObject("modelreactions",$id."_".$compartment.$index);
    if (!defined($mdlrxn)) {
    	my $rxn = $self->template()->searchForReaction($id);
	    if (!defined($rxn)) {
	    	return undef;
	    }
	    $mdlrxn = $self->getObject("modelreactions",$rxn->msid()."_".$compartment.$index);
    }
    return $mdlrxn;
}

=head3 searchForCompartment

Definition:
  Bio::KBase::ObjectAPI::KBaseFBA::Biomass Bio::KBase::ObjectAPI::KBaseFBA::Biomass->searchForCompartment(string:id);
Description:
        Search for compartment in model

=cut

sub searchForCompartment {
    my $self = shift;
    my $id = shift;
    my $index = shift;
    if ($id =~ m/^([a-z]+)(\d*)$/) {
        $id = $1;
        $index = $2;
    } elsif ($id =~ m/^([a-z]+)(\d+)$/) {
        $id = $1;
        $index = $2;
    }
    if (!defined($index)) {
        $index = 0;
    }
    my $mdlcmp = $self->getObject("modelcompartments",$id.$index);
    if (!defined($mdlcmp)) {
        my $cmp = $self->template()->searchForCompartment($id);
            if (!defined($cmp)) {
                return undef;
            }
            $mdlcmp = $self->getObject("modelcompartments",$cmp->id().$index);
    }
    return $mdlcmp;
}

sub merge_models {
	my $self = shift;
	my $parameters = Bio::KBase::ObjectAPI::utilities::args(["models","fbamodel_output_id"], {mixed_bag_model => 0}, @_);
    my $cmpsHash = {
		e0 => $self->addCompartmentToModel({
			compartment => $self->template()->biochemistry()->getObject("compartments","e"),
			pH => 7,
			potential => 0,
			compartmentIndex => 0
		}),
		c0 => $self->addCompartmentToModel({
			compartment => $self->template()->biochemistry()->getObject("compartments","c"),
			pH => 7,
			potential => 0,
			compartmentIndex => 0
		})
	};
	my $totalAbundance = @{$parameters->{models}};
	my $biocount = 1;
	my $primbio = $self->add("biomasses",{
		id => "bio1",
		name => "bio1",
		other => 1,
		dna => 0,
		rna => 0,
		protein => 0,
		cellwall => 0,
		lipid => 0,
		cofactor => 0,
		energy => 0
	});
	my $biomassCompound = $self->template()->getObject("compounds","cpd11416");
	if ($parameters->{mixed_bag_model} == 0) {
		my $biocpd = $self->add("modelcompounds",{
			id => $biomassCompound->id()."_".$cmpsHash->{c0}->id(),
			compound_ref => $biomassCompound->_reference(),
			charge => 0,
			modelcompartment_ref => "~/modelcompartments/id/".$cmpsHash->{c0}->id()
		});
		$primbio->add("biomasscompounds",{
			modelcompound_ref => "~/modelcompounds/id/".$biocpd->id(),
			coefficient => 1
		});
	}
	my $biohash = {};
	$self->other_genome_refs([]);
	for (my $i=0; $i < @{$parameters->{models}}; $i++) {
		print "Loading model ".$parameters->{models}->[$i]."\n";
		my $model = $self->getLinkedObject($parameters->{models}->[$i]);
		my $biomassCpd = $model->getObject("modelcompounds","cpd11416_c0");
		if (!defined($biomassCpd)) {
			$biomassCpd = $model->add("modelcompounds",{
				id => "cpd11416_c0",
				compound_ref => "~/template/compounds/id/cpd11416",
				charge => 0,
				modelcompartment_ref => "~/modelcompartments/id/c0"
			});
			my $biomasses = $model->biomasses();
			for (my $j=0; $j < @{$biomasses}; $j++) {
				$biomasses->[$j]->add("biomasscompounds",{
					modelcompound_ref => "~/modelcompounds/id/cpd11416_c0",
					coefficient => 1
				});
			}
		}
		if ($i == 0) {
			$self->genome_ref($model->genome_ref());
			my $list = [split(/;/,$model->genome_ref())];
			print("genome_ref:".$model->genome_ref()."|".$self->genome_ref()."\n");
			my $newref = "";
			my $first = $list->[0];
			for (my $j=1; $j < @{$list}; $j++) {
				if ($list->[$j] ne $first) {
					if (length($newref) > 0) {
						$newref .= ";";
					}
					$newref .= $list->[$j];
				}
			}
			$self->genome_ref($newref);
		} else {
			$self->other_genome_refs()->[$i-1] = $model->genome_ref();#$model->_wswsid()."/".$model->_wsobjid()."/".$model->_wsversion().";".
			my $list = [split(/;/,$model->genome_ref())];
			print("other_genome_refs:".$model->genome_ref()."|".$self->genome_ref()."\n");
			my $newref = "";
			my $first = $list->[0];
			for (my $j=1; $j < @{$list}; $j++) {
				if ($list->[$j] ne $first) {
					if (length($newref) > 0) {
						$newref .= ";";
					}
					$newref .= $list->[$j];
				}
			}
			$self->other_genome_refs()->[$i-1] = $newref;
		}
		$self->template_refs()->[$i] = $model->template_ref();
		#Adding compartments to community model
		my $cmps = $model->modelcompartments();
		print "Loading compartments\n";
		for (my $j=0; $j < @{$cmps}; $j++) {
			if ($cmps->[$j]->id() ne "e0") {
				my $index = ($i+1);
				if ($parameters->{mixed_bag_model} == 1) {
					$index = 0;
				}
				if ($cmps->[$j]->compartmentIndex() == 1) {
					$index += 20;
				}
				$cmpsHash->{$cmps->[$j]->id()} = $self->addCompartmentToModel({
					compartment => $cmps->[$j]->compartment(),
					pH => 7,
					potential => 0,
					compartmentIndex => $index
				});
			}
		}
		#Adding compounds to community model
		my $translation = {};
		print "Loading compounds\n";
		my $cpds = $model->modelcompounds();
		for (my $j=0; $j < @{$cpds}; $j++) {
			my $cpd = $cpds->[$j];
			my $rootid = $cpd->compound()->id();
			if ($cpd->id() =~ m/(.+)_([a-zA-Z]\d+)/) {
				$rootid = $1;
			}
			my $comcpd = $self->getObject("modelcompounds",$rootid."_".$cmpsHash->{$cpd->modelcompartment()->id()}->id());
			if (!defined($comcpd)) {
				$comcpd = $self->add("modelcompounds",{
					id => $rootid."_".$cmpsHash->{$cpd->modelcompartment()->id()}->id(),
					compound_ref => $cpd->compound_ref(),
					charge => $cpd->charge(),
					formula => $cpd->formula(),
					name => $cpd->name(),
					smiles => $cpd->smiles(),
					inchikey => $cpd->inchikey(),
					dblinks => $cpd->dblinks(),
					aliases => $cpd->aliases(),
					modelcompartment_ref => "~/modelcompartments/id/".$cmpsHash->{$cpd->modelcompartment()->id()}->id()
				});
			}
			$translation->{$cpd->id()} = $comcpd->id();
		}
		print "Loading reactions";
		#Adding reactions to community model
		my $rxns = $model->modelreactions();
		for (my $j=0; $j < @{$rxns}; $j++) {
			my $rxn = $rxns->[$j];
			my $rootid = $rxn->reaction()->msid();
			if ($parameters->{mixed_bag_model} == 1) {
				if ($rootid eq "rxn00000" && $rxn->id() =~ m/(.+)_([a-zA-Z]\d+)/) {
					$rootid = $1;
				}
			} else {
				if ($rxn->id() =~ m/(.+)_([a-zA-Z]\d+)/) {
					$rootid = $1;
				}
			}
			my $originalcmpid = $rxn->modelcompartment()->id();
			if ($originalcmpid eq "e0") {
				$originalcmpid = "c0";
			}
			my $comrxn = $self->getObject("modelreactions",$rootid."_".$cmpsHash->{$originalcmpid}->id());
			if (!defined($comrxn)) {
				$comrxn = $self->add("modelreactions",{
					id => $rootid."_".$cmpsHash->{$originalcmpid}->id(),
					reaction_ref => $rxn->reaction_ref(),
					direction => $rxn->direction(),
					protons => $rxn->protons(),
					modelcompartment_ref => "~/modelcompartments/id/".$cmpsHash->{$originalcmpid}->id(),
					probability => $rxn->probability()
				});
				for (my $k=0; $k < @{$rxn->modelReactionReagents()}; $k++) {
					$comrxn->add("modelReactionReagents",{
						modelcompound_ref => "~/modelcompounds/id/".$translation->{$rxn->modelReactionReagents()->[$k]->modelcompound()->id()},
						coefficient => $rxn->modelReactionReagents()->[$k]->coefficient()
					});
				}
			}
			for (my $k=0; $k < @{$rxn->modelReactionProteins()}; $k++) {
				$comrxn->add("modelReactionProteins",$rxn->modelReactionProteins()->[$k]);
			}
		}
		print "Loading biomass";
		#Adding biomass to community model
		my $bios = $model->biomasses();
		for (my $j=0; $j < @{$bios}; $j++) {
			if ($parameters->{mixed_bag_model} == 0) {
				my $bio = $bios->[$j]->cloneObject();
				$bio->parent($self);
				for (my $k=0; $k < @{$bio->biomasscompounds()}; $k++) {
					$bio->biomasscompounds()->[$k]->modelcompound_ref("~/modelcompounds/id/".$translation->{$bios->[$j]->biomasscompounds()->[$k]->modelcompound()->id()});
				}
				$bio = $self->add("biomasses",$bio);
				$biocount++;
				$bio->id("bio".$biocount);
				$bio->name("bio".$biocount);
			} elsif ($j == 0) {
				for (my $k=0; $k < @{$bios->[$j]->biomasscompounds()}; $k++) {
					if (defined($biohash->{$translation->{$bios->[$j]->biomasscompounds()->[$k]->modelcompound()->id()}})) {
						$biohash->{$translation->{$bios->[$j]->biomasscompounds()->[$k]->modelcompound()->id()}}->coefficient($biohash->{$translation->{$bios->[$j]->biomasscompounds()->[$k]->modelcompound()->id()}}->coefficient() + $bios->[$j]->biomasscompounds()->[$k]->coefficient());
					} else {
						$biohash->{$translation->{$bios->[$j]->biomasscompounds()->[$k]->modelcompound()->id()}} = $primbio->add("biomasscompounds",{
							modelcompound_ref => "~/modelcompounds/id/".$translation->{$bios->[$j]->biomasscompounds()->[$k]->modelcompound()->id()},
							coefficient => $bios->[$j]->biomasscompounds()->[$k]->coefficient()
						});
					}
				}
			}
		}
		print "Loading primary biomass";
		#Adding biomass component to primary composite biomass reaction
		if ($parameters->{mixed_bag_model} == 0) {
			$primbio->add("biomasscompounds",{
				modelcompound_ref => "~/modelcompounds/id/".$translation->{$biomassCpd->id()},
				coefficient => -1/$totalAbundance
			});
		}
	}
	if ($parameters->{mixed_bag_model} == 1) {
		for (my $k=0; $k < @{$primbio->biomasscompounds()}; $k++) {
			$primbio->biomasscompounds()->[$k]->coefficient($primbio->biomasscompounds()->[$k]->coefficient()/$totalAbundance);
		}
	}
	print "Merge complete!";
}

sub merge_in_reaction {
	my ($self,$rxn) = @_;
	my $newrxn = $self->getObject("modelreactions",$rxn->id());
	if (!defined($newrxn)) {
		#Adding missing compounds from reagent list
		my $rgts = $rxn->modelReactionReagents();
		for (my $i=0; $i < @{$rgts}; $i++) {
			my $newcpd = $self->getObject("modelcompounds",$rgts->[$i]->modelcompound()->id());
			if (!defined($newcpd)) {
				#Adding missing compartments from reagent list
				my $newcmp = $rgts->[$i]->modelcompound()->modelcompartment();
				$newcmp = $self->getObject("modelcompartments",$newcmp->id());
				if (!defined($newcmp)) {
					$newcmp = $rgts->[$i]->modelcompound()->modelcompartment()->cloneObject();
					$newcmp->parent($self);
					$self->add("modelcompartments",$newcmp);
				}
				$newcpd = $rgts->[$i]->modelcompound()->cloneObject();
				$newcpd->parent($self);
				$self->add("modelcompounds",$newcpd);
			}
		}
		#Adding the reaction itself
		my $clonedrxn = $rxn->cloneObject();
		$clonedrxn->parent($self);
		return $self->add("modelreactions",$clonedrxn);
	}
	#Reaction already exists - just syncing associated gene list
	my $genehash = $newrxn->gene_hash();
	my $prots = $rxn->modelReactionProteins();
	for (my $i=0; $i < @{$prots}; $i++) {
		my $match = 1;
		my $sus = $prots->[$i]->modelReactionProteinSubunits();
		for (my $j=0; $j < @{$sus}; $j++) {
			my $genes = $sus->[$j]->features();
			for (my $k=0; $k < @{$genes}; $k++) {
				if (!defined($genehash->{$genes->[$k]->id()})) {
					$match = 0;
				}
			}
		}
		if ($match == 0) {
			$newrxn->add("modelReactionProteins",$prots->[$i]->cloneObject());
			$genehash = $newrxn->gene_hash();
		}
	}
}

=head3 edit_metabolic_model

Definition:
    $self->edit_metabolic_model({
    	reactions_to_remove => [],
    	reactions_to_add => [],
    	reactions_to_modify => []
    });
Description:
    Function for manually editing a metabolic model

=cut
sub edit_metabolic_model {
	my ($self,$params) = @_;
    $params = Bio::KBase::ObjectAPI::utilities::args([], {
    	compounds_to_add => [],
    	compounds_to_change => [],
    	biomasses_to_add => [],
    	biomass_compounds_to_change => [],
    	reactions_to_remove => [],
    	reactions_to_change => [],
    	reactions_to_add => [],
    	edit_compound_stoichiometry => []
    },$params);
	my $output = {
		id => Data::UUID->new()->create_str(),
    	timestamp => DateTime->now()->datetime(),
		compounds_added => [],
		compounds_changed => [],
		biomass_added => [],
		biomass_compounds_removed => [],
		biomass_compounds_added => [],
		biomass_compounds_changed => [],
		reactions_added => [],
		reactions_changed => [],
		reactions_removed => []
	};
	Bio::KBase::utilities::log("Adding specified compounds");
	my $uuid = Data::UUID->new()->create_str();
	my $translation = {};
	for (my $i=0; $i < @{$params->{compounds_to_add}}; $i++) {
		if (defined($params->{compounds_to_add}->[$i]->{add_compartment_id})) {
			if (ref($params->{compounds_to_add}->[$i]->{add_compartment_id}) eq "ARRAY") {
				$params->{compounds_to_add}->[$i]->{add_compartment_id} = $params->{compounds_to_add}->[$i]->{add_compartment_id}->[0];
			}
		}
		my $cpdref = "~/template/compounds/id/cpd00000";
		$params->{compounds_to_add}->[$i]->{add_compound_id} =~ s/_[a-z]\d+$//;
		if ($params->{compounds_to_add}->[$i]->{add_compound_id} =~ m/cpd\d+/) {
			my $cpdobj = $self->template()->getObject("compounds",$params->{compounds_to_add}->[$i]->{add_compound_id});
			if (defined($cpdobj)) {
				$cpdref = "~/template/compounds/id/".$params->{compounds_to_add}->[$i]->{add_compound_id};
				if (!defined($params->{compounds_to_add}->[$i]->{add_compound_charge}) || $params->{compounds_to_add}->[$i]->{add_compound_charge} eq "") {
					$params->{compounds_to_add}->[$i]->{add_compound_charge} = $cpdobj->defaultCharge();
				}
				if (!defined($params->{compounds_to_add}->[$i]->{add_compound_name}) || $params->{compounds_to_add}->[$i]->{add_compound_name} eq "") {
					$params->{compounds_to_add}->[$i]->{add_compound_name} = $cpdobj->name();
				}
				if (!defined($params->{compounds_to_add}->[$i]->{add_compound_formula}) || $params->{compounds_to_add}->[$i]->{add_compound_formula} eq "") {
					$params->{compounds_to_add}->[$i]->{add_compound_formula} = $cpdobj->formula();
				}
			}
		}
		if (!defined $params->{compounds_to_add}->[$i]->{add_compartment_id}){
			Bio::KBase::utilities::error("Must specify a compartment id for new compounds");
		}
		my $mdlcpd = $self->add("modelcompounds",{
			id => $params->{compounds_to_add}->[$i]->{add_compound_id}."_".$params->{compounds_to_add}->[$i]->{add_compartment_id},
			modelcompartment_ref => "~/modelcompartments/id/".$params->{compounds_to_add}->[$i]->{add_compartment_id},
			compound_ref => $cpdref,
			charge => $params->{compounds_to_add}->[$i]->{add_compound_charge},
			formula => $params->{compounds_to_add}->[$i]->{add_compound_formula},
			name => $params->{compounds_to_add}->[$i]->{add_compound_name}
		});
		$translation->{$params->{compounds_to_add}->[$i]->{add_compound_id}} = $mdlcpd->id();
		push(@{$output->{compounds_added}},$mdlcpd->id());
	}
	Bio::KBase::utilities::log("Changing specified compounds");
	for (my $i=0; $i < @{$params->{compounds_to_change}}; $i++) {
		if (defined($params->{compounds_to_change}->[$i]->{compound_id})) {
			if (ref($params->{compounds_to_change}->[$i]->{compound_id}) eq "ARRAY") {
				$params->{compounds_to_change}->[$i]->{compound_id} = $params->{compounds_to_change}->[$i]->{compound_id}->[0];
			}
		}
		my $id = $params->{compounds_to_change}->[$i]->{compound_id};
		if (defined($translation->{$id})) {
			$id = $translation->{$id};
		}
		my $cpd = $self->getObject("modelcompounds",$id);
		if (defined($cpd)) {
			if (defined($params->{compounds_to_change}->[$i]->{compound_name}) && $params->{compounds_to_change}->[$i]->{compound_name} ne "") {
				$cpd->name($params->{compounds_to_change}->[$i]->{compound_name});
			}
			if (defined($params->{compounds_to_change}->[$i]->{compound_charge}) && $params->{compounds_to_change}->[$i]->{compound_charge} ne "") {
				$cpd->charge($params->{compounds_to_change}->[$i]->{compound_charge});
			}
			if (defined($params->{compounds_to_change}->[$i]->{compound_formula}) && $params->{compounds_to_change}->[$i]->{compound_formula} ne "") {
				$cpd->formula($params->{compounds_to_change}->[$i]->{compound_formula});
			}
			push(@{$output->{compounds_changed}},$cpd->id());
		}
	}
	Bio::KBase::utilities::log("Adding biomass reactions");
	my $tbio = $self->template()->biomasses()->[0];
	my $hash;
	my $list = ["name","dna","rna","protein","lipid","cellwall","cofactor","energy","other"];
	for (my $j=0; $j < @{$list}; $j++) {
		my $function = $list->[$j];
		$hash->{$function} = $tbio->$function();
	}
	for (my $i=0; $i < @{$params->{biomasses_to_add}}; $i++) {
		for (my $j=0; $j < @{$list}; $j++) {
			my $function = $list->[$j];
			$tbio->$function($hash->{$function});
			if (defined($params->{biomasses_to_add}->[$i]->{"biomass_".$list->[$j]})) {
				$tbio->$function($params->{biomasses_to_add}->[$i]->{"biomass_".$list->[$j]});
			}
		}
		my $bio = $tbio->addBioToModel({
			gc => $self->genome()->gc_content(),
			model => $self
		});
		push(@{$output->{biomass_added}},$bio->id());
	}
	Bio::KBase::utilities::log("Changing specified biomass compounds");
	for (my $i=0; $i < @{$params->{biomass_compounds_to_change}}; $i++) {
		if (defined($params->{biomass_compounds_to_change}->[$i]->{biomass_id})) {
			if (ref($params->{biomass_compounds_to_change}->[$i]->{biomass_id}) eq "ARRAY") {
				$params->{biomass_compounds_to_change}->[$i]->{biomass_id} = $params->{biomass_compounds_to_change}->[$i]->{biomass_id}->[0];
			}
		}
		if (defined($params->{biomass_compounds_to_change}->[$i]->{biomass_compound_id})) {
			if (ref($params->{biomass_compounds_to_change}->[$i]->{biomass_compound_id}) eq "ARRAY") {
				$params->{biomass_compounds_to_change}->[$i]->{biomass_compound_id} = $params->{biomass_compounds_to_change}->[$i]->{biomass_compound_id}->[0];
			}
		}
		my $biocpd = $params->{biomass_compounds_to_change}->[$i];
		my $bio = $self->getObject("biomasses",$biocpd->{biomass_id});
		if (defined($bio)) {
			my $biocpds = $bio->biomasscompounds();
			my $found = 0;
			for (my $j=0; $j < @{$biocpds}; $j++) {
				if ($biocpds->[$j]->modelcompound_ref() =~ m/([^\/]+)$/) {
					if ($1 eq $biocpd->{biomass_compound_id}) {
						$found = 1;
						if ($biocpd->{biomass_coefficient} == 0) {
							push(@{$output->{biomass_compounds_removed}},$biocpd->{biomass_compound_id});
							$bio->remove("biomasscompounds",$biocpds->[$j]);
						} else {
							push(@{$output->{biomass_compounds_changed}},$biocpd->{biomass_compound_id});
							$biocpds->[$j]->coefficient($biocpd->{biomass_coefficient});
						}
					}
				}
			}
			if ($found == 0 && $biocpd->{biomass_coefficient} != 0) {
				push(@{$output->{biomass_compounds_added}},$biocpd->{biomass_compound_id});
				$bio->add("biomasscompounds",{
					modelcompound_ref => "~/modelcompounds/id/".$biocpd->{biomass_compound_id},
					coefficient => $biocpd->{biomass_coefficient}
				});
			}
		}
	}
	Bio::KBase::utilities::log("Removing reactions");
	for (my $i=0; $i < @{$params->{reactions_to_remove}}; $i++) {
		my $rxnobj = $self->getObject("modelreactions",$params->{reactions_to_remove}->[$i]);
    	if (defined($rxnobj)) {
#    		if (!defined($self->deleted_reactions()->{$rxnobj->id()})) {
#    			$self->deleted_reactions()->{$rxnobj->id()} = $rxnobj->serializeToDB();
#    		}
#    		$self->deleted_reactions()->{$rxnobj->id()}->{edits}->{$uuid} = {
#				status => "deleted",
#				reaction => $params->{reactions_to_remove}->[$i],
#			    compartment => $rxnobj->modelCompartmentLabel(),
#			    direction => [$rxnobj->direction(),undef],
#			    gpr => [$rxnobj->gprString(),undef],
#			    equation => [$rxnobj->equation(),undef],
#			    pathway => [$rxnobj->pathway(),undef],
#			    name => [$rxnobj->name(),undef],
#			    reference => [$rxnobj->reference(),undef],
#			};
    		$self->remove("modelreactions",$rxnobj);
    		push(@{$output->{reactions_removed}},$params->{reactions_to_remove}->[$i]);
    	}
	}
	Bio::KBase::utilities::log("Adding reactions");
	for (my $i=0; $i < @{$params->{reactions_to_add}}; $i++) {
		if (defined($params->{reactions_to_add}->[$i]->{reaction_compartment_id})) {
			if (ref($params->{reactions_to_add}->[$i]->{reaction_compartment_id}) eq "ARRAY") {
				$params->{reactions_to_add}->[$i]->{reaction_compartment_id} = $params->{reactions_to_add}->[$i]->{reaction_compartment_id}->[0];
			}
		}
		my $rxnadd = $params->{reactions_to_add}->[$i];
		$rxnadd->{add_reaction_id} =~ s/_[a-z]\d+$//;
		if (!defined($rxnadd->{reaction_compartment_id}) || $rxnadd->{reaction_compartment_id} eq "") {
			$rxnadd->{reaction_compartment_id} = "c0";
		}
		my $rxnobj = $self->template()->getObject("reactions",$rxnadd->{add_reaction_id}."_".substr($rxnadd->{reaction_compartment_id},0,1));
		if (!defined($rxnobj) && $rxnadd->{add_reaction_id} =~ m/rxn\d+/) {
			$rxnobj = $self->template()->biochemistry()->getObject("reactions",$rxnadd->{add_reaction_id});
		}
		my $rxnref = "~/template/reactions/id/rxn00000_c";
		if (!defined $rxnadd->{reaction_compartment_id}){
			Bio::KBase::utilities::error("Must specify a compartment id for new reactions");
		}
		if (defined($rxnobj)) {
			if (!defined($rxnadd->{add_reaction_name}) || $rxnadd->{add_reaction_name} eq "") {
				$rxnadd->{add_reaction_name} = $rxnobj->name();
			}
			if (!defined($rxnadd->{add_reaction_direction}) || $rxnadd->{add_reaction_direction} eq "") {
				$rxnadd->{add_reaction_direction} = $rxnobj->direction();
			}
			if ($rxnobj->id() =~ m/rxn\d+_[a-z]+/) {
				$rxnref = "~/template/reactions/id/".$rxnobj->id();
			}
		} else {
			if (!defined($rxnadd->{add_reaction_name}) || $rxnadd->{add_reaction_name} eq "") {
				$rxnadd->{add_reaction_name} = $rxnadd->{add_reaction_id};
			}
			if (!defined($rxnadd->{add_reaction_direction}) || $rxnadd->{add_reaction_direction} eq "") {
				$rxnadd->{add_reaction_direction} = "=";
			}
		}
		my $mdlrxnobj = $self->add("modelreactions",{
			id => $rxnadd->{add_reaction_id}."_".$rxnadd->{reaction_compartment_id},
			reaction_ref => $rxnref,
			name => $rxnadd->{add_reaction_name},
			direction => $rxnadd->{add_reaction_direction},
			modelcompartment_ref => "~/modelcompartments/id/".$rxnadd->{reaction_compartment_id}
		});		
		if (defined($rxnadd->{equation})) {
			$self->LoadExternalReactionEquation({
				equation => $rxnadd->{equation},
				compounds => {},
				reaction => $mdlrxnobj
			});
		} elsif (defined($rxnobj)) {
			my $reactants;
			if ($rxnobj->id() =~ m/rxn\d+_[a-z]+/) {
				$reactants = $rxnobj->templateReactionReagents();
				for (my $i=0; $i < @{$reactants}; $i++) {
					my $reactantobj = $self->getObject("modelcompounds",$reactants->[$i]->templatecompcompound()->id().substr($rxnadd->{reaction_compartment_id},1));
					if (!defined($reactantobj)) {
						$reactantobj = $self->add("modelcompounds",{
							id => $reactants->[$i]->templatecompcompound()->id().substr($rxnadd->{reaction_compartment_id},1),
							compound_ref => "~/template/compounds/".$reactants->[$i]->templatecompcompound()->templatecompound()->id(),
							aliases => [],
							name => $reactants->[$i]->templatecompcompound()->templatecompound()->name(),
							charge => $reactants->[$i]->templatecompcompound()->charge(),
							maxuptake => $reactants->[$i]->templatecompcompound()->maxuptake(),
							formula => $reactants->[$i]->templatecompcompound()->formula(),
							modelcompartment_ref => "~/modelcompartments/id/".$reactants->[$i]->templatecompcompound()->templatecompartment()->id().substr($rxnadd->{reaction_compartment_id},1)
						});
					}
					$mdlrxnobj->add("modelReactionReagents",{
						modelcompound_ref => "~/modelcompounds/id/".$reactantobj->id(),
						coefficient => $reactants->[$i]->coefficient()
					});
				}
			} else {
				$reactants = $rxnobj->reagents();
				my $multicomp = 0;
				my $firstcomp = $reactants->[0]->compartment()->id();
				for (my $i=1; $i < @{$reactants}; $i++) {
					if ($reactants->[$i]->compartment()->id() ne $firstcomp) {
						$multicomp = 1;
					}
				}
				for (my $i=0; $i < @{$reactants}; $i++) {
					my $rxnindex = substr($rxnadd->{reaction_compartment_id},1);
					my $templatecomp = $reactants->[$i]->compartment()->id();
					my $reactcomp = $templatecomp.$rxnindex;
					if ($multicomp == 0 || $templatecomp eq "c") {
						$reactcomp = $rxnadd->{reaction_compartment_id};
					}
					my $cpdid = $reactants->[$i]->compound()->id();
					$cpdid = $cpdid."_".$reactcomp;
					my $rxnname = $reactants->[$i]->compound()->name();
					$rxnname = $rxnname."_".$reactcomp;
					my $reactantobj = $self->getObject("modelcompounds",$cpdid);
					if (!defined($reactantobj)) {
						my $cpdref = "~/template/compounds/cpd00000";
						if (defined($self->template()->getObject("compounds",$reactants->[$i]->compound()->id()))) {
							$cpdref = "~/template/compounds/".$reactants->[$i]->compound()->id();
						}
						$reactantobj = $self->add("modelcompounds",{
							id => $cpdid,
							compound_ref => $cpdref,
							aliases => [],
							name => $rxnname,
							charge => $reactants->[$i]->compound()->defaultCharge(),
							maxuptake => 100,
							formula => $reactants->[$i]->compound()->formula(),
							modelcompartment_ref => "~/modelcompartments/id/".$reactcomp
						});
					}
					$mdlrxnobj->add("modelReactionReagents",{
						modelcompound_ref => "~/modelcompounds/id/".$reactantobj->id(),
						coefficient => $reactants->[$i]->coefficient()
					});
				}
			}
		}
		if (defined($rxnadd->{add_reaction_gpr})) {
			$mdlrxnobj->loadGPRFromString($rxnadd->{add_reaction_gpr});
		}
		push(@{$output->{reactions_added}},$mdlrxnobj->id());
	}
	Bio::KBase::utilities::log("Changing reactions");
	my $rxntranslation;
	for (my $i=0; $i < @{$params->{reactions_to_change}}; $i++) {
		if (defined($params->{reactions_to_change}->[$i]->{change_reaction_id})) {
			if (ref($params->{reactions_to_change}->[$i]->{change_reaction_id}) eq "ARRAY") {
				$params->{reactions_to_change}->[$i]->{change_reaction_id} = $params->{reactions_to_change}->[$i]->{change_reaction_id}->[0];
			}
		}
		my $mdlrxn = $self->getObject("modelreactions",$params->{reactions_to_change}->[$i]->{change_reaction_id});
		if (defined($mdlrxn)) {
			if (defined($params->{reactions_to_change}->[$i]->{change_reaction_name})) {
				$mdlrxn->name($params->{reactions_to_change}->[$i]->{change_reaction_name});
			}
			if (defined($params->{reactions_to_change}->[$i]->{change_reaction_direction})) {
				$mdlrxn->direction($params->{reactions_to_change}->[$i]->{change_reaction_direction});
			}
			if (defined($params->{reactions_to_change}->[$i]->{change_reaction_gpr})) {
				$mdlrxn->loadGPRFromString($params->{reactions_to_change}->[$i]->{change_reaction_gpr});
			}
			$rxntranslation->{$params->{reactions_to_change}->[$i]->{change_reaction_id}} = $mdlrxn->id();
			push(@{$output->{reactions_changed}},$mdlrxn->id());
		}
	}
	Bio::KBase::utilities::log("Editing reactants");
	for (my $i=0; $i < @{$params->{edit_compound_stoichiometry}}; $i++) {
		if (defined($params->{edit_compound_stoichiometry}->[$i]->{stoich_reaction_id})) {
			if (ref($params->{edit_compound_stoichiometry}->[$i]->{stoich_reaction_id}) eq "ARRAY") {
				$params->{edit_compound_stoichiometry}->[$i]->{stoich_reaction_id} = $params->{edit_compound_stoichiometry}->[$i]->{stoich_reaction_id}->[0];
			}
		}
		if (defined($params->{edit_compound_stoichiometry}->[$i]->{stoich_compound_id})) {
			if (ref($params->{edit_compound_stoichiometry}->[$i]->{stoich_compound_id}) eq "ARRAY") {
				$params->{edit_compound_stoichiometry}->[$i]->{stoich_compound_id} = $params->{edit_compound_stoichiometry}->[$i]->{stoich_compound_id}->[0];
			}
		}
		if (defined($rxntranslation->{$params->{edit_compound_stoichiometry}->[$i]->{stoich_reaction_id}})) {
			$params->{edit_compound_stoichiometry}->[$i]->{stoich_reaction_id} = $rxntranslation->{$params->{edit_compound_stoichiometry}->[$i]->{stoich_reaction_id}};
		}
		my $mdlrxn = $self->getObject("modelreactions",$params->{edit_compound_stoichiometry}->[$i]->{stoich_reaction_id});
		if (defined($mdlrxn)) {
			if (defined($translation->{$params->{edit_compound_stoichiometry}->[$i]->{stoich_compound_id}})) {
				$params->{edit_compound_stoichiometry}->[$i]->{stoich_compound_id} = $translation->{$params->{edit_compound_stoichiometry}->[$i]->{stoich_compound_id}};
			}
			my $mdlcpd = $self->getObject("modelcompounds",$params->{edit_compound_stoichiometry}->[$i]->{stoich_compound_id});
			if (defined($mdlcpd)) {
				my $reactants = $mdlrxn->modelReactionReagents();
				my $found = 0;
				for (my $j=0; $j < @{$reactants}; $j++) {
					if ($reactants->[$j]->modelcompound()->id() eq $params->{edit_compound_stoichiometry}->[$i]->{stoich_compound_id}) {
						$found = 1;
						if ($params->{edit_compound_stoichiometry}->[$i]->{stoich_coefficient} == 0) {
							$mdlrxn->remove("modelReactionReagents",$reactants->[$j]);
						} else {
							$reactants->[$j]->coefficient($params->{edit_compound_stoichiometry}->[$i]->{stoich_coefficient});
						}
						last;
					}
				}
				if ($found == 0 && $params->{edit_compound_stoichiometry}->[$i]->{stoich_coefficient} != 0) {
					$mdlrxn->add("modelReactionReagents",{
						modelcompound_ref => "~/modelcompounds/id/".$params->{edit_compound_stoichiometry}->[$i]->{stoich_compound_id},
						coefficient => $params->{edit_compound_stoichiometry}->[$i]->{stoich_coefficient}
					});
				}
			}
			push(@{$output->{reactions_changed}},$mdlrxn->id());
		}
	}
    #push(@{$self->model_edits()},$output);
	return $output;
}

=head3 undo_edit

Definition:
    $self->undo_edit({});
Description:
    Undoes and removes the last edit from the model

=cut
sub undo_edit {
	my ($params) = @_;
	$params = Bio::KBase::ObjectAPI::utilities::args([], {}, @_);

}

=head3 translate_model

Definition:
    $self->translate_model(ProteomeComparison:comparison);
Description:
    Translates model to new genome based on proteome comparison

=cut
sub translate_model {
	my $self = shift;
	my $args = Bio::KBase::ObjectAPI::utilities::args(["proteome_comparison"], {
		keep_nogene_rxn => 1,
		translation_policy => "translate_only"
	}, @_);
	my $protcomp = $args->{proteome_comparison};
	my $genome = $self->genome();
	my $ftrs = $genome->features();
	my $numftrs = @{$ftrs};
	my $ftrhash;
	for (my $i=0; $i < @{$ftrs}; $i++) {
		$ftrhash->{$ftrs->[$i]->id()} = 1;
	}
	my $onewgenome = $self->getLinkedObject($protcomp->{genome1ref});
	$ftrs = $onewgenome->features();
	my $matchcount = 0;
	for (my $i=0; $i < @{$ftrs}; $i++) {
		if (defined($ftrhash->{$ftrs->[$i]->id()})) {
			$matchcount++;
		}
	}
	my $newgenome = $self->getLinkedObject($protcomp->{genome2ref});
	$ftrs = $newgenome->features();
	my $omatchcount = 0;
	for (my $i=0; $i < @{$ftrs}; $i++) {
		if (defined($ftrhash->{$ftrs->[$i]->id()})) {
			$omatchcount++;
		}
	}
	my $ref = $protcomp->{genome2ref};
	my $map = $protcomp->{proteome1map};
	my $list = $protcomp->{proteome1names};
	my $data = $protcomp->{data1};
	my $omap = $protcomp->{proteome2map};
	my $olist = $protcomp->{proteome2names};
	my $odata = $protcomp->{data2};
	if ($omatchcount >  $matchcount) {
		$newgenome = $onewgenome;
		$matchcount = $omatchcount;
		$ref = $protcomp->{genome1ref};
		$map = $protcomp->{proteome2map};
		$list = $protcomp->{proteome2names};
		$data = $protcomp->{data2};
		$omap = $protcomp->{proteome1map};
		$olist = $protcomp->{proteome1names};
		$odata = $protcomp->{data1};
	}
	if ($numftrs == 0) {
		Bio::KBase::ObjectAPI::utilities::error("The model is associated with a genome that contains no features!");
	}
	print "Fraction of matching features between model genomes and proteome comparison:".$matchcount/$numftrs."\n";
	if ($matchcount/$numftrs < 0.8) {
		Bio::KBase::ObjectAPI::utilities::error("Proteome comparison does not involve genome used in model!");
	}
	my $translate;
	$ftrhash = {};
	for(my $i=0; $i < @{$data}; $i++) {
		for (my $j=0; $j < @{$data->[$i]}; $j++) {
			if ($data->[$i]->[$j]->[2] == 100) {
				push(@{$translate->{$list->[$i]}},$olist->[$data->[$i]->[$j]->[0]]);
				if ($args->{translation_policy} eq "add_reactions_for_unique_genes") {
					$ftrhash->{$olist->[$data->[$i]->[$j]->[0]]} = 1;
				}
			}
		}
	}
	my $reactions = $self->modelreactions();
	for (my $i=0; $i < @{$reactions}; $i++) {
		my $rxn = $reactions->[$i];
		my $prots = $rxn->modelReactionProteins();
		my $keeprxn = 0;
		my $rxnftrs = 0;
		for (my $j=0; $j < @{$prots}; $j++) {
			my $sus = $prots->[$j]->modelReactionProteinSubunits();
			my $keep = 0;
			for (my $k=0; $k < @{$sus}; $k++) {
				my $ftrs = $sus->[$k]->features();
				my $newftrs = [];
				for (my $m=0; $m < @{$ftrs}; $m++) {
					$rxnftrs = 1;
					if (defined($translate->{$ftrs->[$m]->id()})) {
						foreach my $gene (@{$translate->{$ftrs->[$m]->id()}}) {
							my $newftr = $newgenome->getObject("features",$gene);
							if ($args->{translation_policy} eq "reconcile") {
								$ftrhash->{$newftr->id()} = 1;
							}
							push(@{$newftrs},$newftr->_reference());
						}
					}
				}
				if (@{$newftrs} > 0) {
					$keep = 1;
					$keeprxn = 1;
				}
				$sus->[$k]->feature_refs($newftrs);
			}
			if ($keep == 0) {
				$rxn->removeLinkArrayItem("modelReactionProteins",$prots->[$j]);
			}
		}
		if (@{$rxn->modelReactionProteins()} == 0 || $keeprxn == 0) {
			if ($rxnftrs == 1 || $args->{keep_nogene_rxn} == 0) {
				$self->remove("modelreactions",$rxn);
			}
		}
	}
	$self->genome_ref($protcomp->{'_reference'}.";".$ref);
	$self->name($newgenome->scientific_name());
	$self->genome($newgenome);
	if ($args->{translation_policy} ne "translate_only") {
		my $extra_features = [];
		$ftrs = $newgenome->features();
		for (my $i=0; $i < @{$ftrs}; $i++) {
			if (!defined($ftrhash->{$ftrs->[$i]->id()})) {
				push(@{$extra_features},$ftrs->[$i]);
			}
		}
		$self->template()->extend_model_from_features({
			model => $self,
			features => $extra_features
		});
	}
	return {};
}

sub correct_ref_chain {
	my $self = shift;
	my $ref = shift;
	my $value = shift;
	my $array = [split(";",$value)];
	if ($array->[0] ne $ref) {
		unshift(@{$array},$ref);
	}
	return join(";",@{$array});
}

sub fix_ref_chains {
	my $self = shift;
	#Check if this object came from the workspace 
	my $ref;
	if (length($self->wsmeta) > 0) {
		$ref = $self->_wswsid()."/".$self->_wsobjid()."/".$self->_wsversion();
	}
	#Turning all object refs into ref chains to ensure object can be saved
    if (defined($ref)) {
    	$self->genome_ref($self->correct_ref_chain($ref,$self->genome_ref()));
    	if (defined($self->metagenome_ref())) {
    		$self->metagenome_ref($self->correct_ref_chain($ref,$self->metagenome_ref()));
    	}
    	print "OLDREF:".$self->template_ref()."\n";
    	$self->template_ref($self->correct_ref_chain($ref,$self->template_ref()));
    	print "NEWREF:".$self->template_ref()."\n";
    	my $new_array = [];
    	foreach my $new_ref (@{$self->other_genome_refs()}) {
    		push(@{$new_array},$self->correct_ref_chain($ref,$new_ref));
    	}
		$self->other_genome_refs($new_array);
		$new_array = [];
    	foreach my $new_ref (@{$self->template_refs()}) {
    		push(@{$new_array},$self->correct_ref_chain($ref,$new_ref));
    	}
		$self->template_refs($new_array);
		foreach my $gapfill (@{$self->gapfillings()}) {
			if (defined($gapfill->fba_ref()) && length($gapfill->fba_ref()) > 0) {
				$gapfill->fba_ref($self->correct_ref_chain($ref,$gapfill->fba_ref()));
			}
			if (defined($gapfill->media_ref())) {
				$gapfill->media_ref($self->correct_ref_chain($ref,$gapfill->media_ref()));
			}
		}
		foreach my $gapgen (@{$self->gapgens()}) {
			if (defined($gapgen->fba_ref())) {
				$gapgen->fba_ref($self->correct_ref_chain($ref,$gapgen->fba_ref()));
			}
			if (defined($gapgen->media_ref())) {
				$gapgen->media_ref($self->correct_ref_chain($ref,$gapgen->media_ref()));
			}
		}
    }
}

sub translate_to_localrefs {
	my $self = shift;
	my %seen = ();
	$self->initialize_attributes();
	my $compartments = $self->modelcompartments();
    for (my $i=0; $i < @{$compartments}; $i++) {
		if ($compartments->[$i]->compartment_ref() =~ m/\/([^\/]+)$/) {
			my $ind = $compartments->[$i]->compartmentIndex();
			if (! $seen{ $1.$ind }++) {
				$compartments->[$i]->compartment_ref("~/template/compartments/id/" . $1);
			} else {
				print "Removeing duplicated compartment: ".$compartments->[$i]->label()."\n";
				$self->remove("modelcompartments",$compartments->[$i]);
			}
		}
    }
	my $compounds = $self->modelcompounds();
    for (my $i=0; $i < @{$compounds}; $i++) {
		if ($compounds->[$i]->compound_ref() =~ m/\/([^\/]+)$/) {
			$compounds->[$i]->compound_ref("~/template/compounds/id/".$1);
		}
    }
    my $reactions = $self->modelreactions();
    for (my $i=0; $i < @{$reactions}; $i++) {
		my $array = [split(/_/,$reactions->[$i]->id())];
	 	my $comp = pop(@{$array});
	 	$comp =~ s/\d+//;
		if ($reactions->[$i]->reaction_ref() =~ m/\/([^\/]+?)(_[^\/])?$/) {
			$reactions->[$i]->reaction_ref("~/template/reactions/id/".$1."_".$comp);
		}
		my $prots = $reactions->[$i]->modelReactionProteins();
    	for (my $j=0; $j < @{$prots}; $j++) {
    		if (defined($prots->[$j]->complex_ref()) && $prots->[$j]->complex_ref() =~ m/\/([^\/]+)$/) {
    			$prots->[$j]->complex_ref("~/template/complexes/name/".$1);
    		}
    		my $subunits = $prots->[$j]->modelReactionProteinSubunits();
    		for (my $k=0; $k < @{$subunits}; $k++) {
    			my $ftrrefs = $subunits->[$k]->feature_refs();
    			for (my $m=0; $m < @{$ftrrefs}; $m++) {
    				if ($ftrrefs->[$m] =~ m/\/([^\/]+)$/) {
    					$ftrrefs->[$m] = "~/genome/features/id/".$1;
    				}
    			}
    		}
    	}
    }
}

sub update_from_old_versions {
	my $self = shift;
	if ($self->template_ref() eq "277/31/1") {
		$self->template_ref("12998/4/1");
	}
	my $gfs = $self->gapfillings();
	my $updated = 1;
	for (my $i=0; $i < @{$gfs}; $i++) {
		if (length($gfs->[$i]->gapfill_ref()) > 0) {
			$updated = 0;
		} elsif (length($gfs->[$i]->fba_ref()) > 0) {
			$updated = 0;
		}
	}
	if ($updated == 0) {
		print "Updating model gapfilling data!\n";
		for (my $i=0; $i < @{$gfs}; $i++) {
			$self->remove("gapfillings",$gfs->[$i]);
		}
		for (my $i=0; $i < @{$gfs}; $i++) {
			my $fbobj;
			if (length($gfs->[$i]->gapfill_ref()) > 0) {
				$fbobj = $gfs->[$i]->gapfill();
			} elsif (length($gfs->[$i]->fba_ref()) > 0) {
				$fbobj = $gfs->[$i]->fba();
			}
			if (defined($fbobj) && defined($fbobj->gapfillingSolutions()->[0])) {
				print "Updating older style model gapfilling to new formats.\n";
				$fbobj->fbamodel($self);
				$self->add_gapfilling({
					object => $fbobj,
					id => "gf.".$i,
					solution_to_integrate => 0
				});
			}
		}
	}
}

__PACKAGE__->meta->make_immutable;
1;
