########################################################################
# Bio::KBase::ObjectAPI::KBaseFBA::ModelTemplate - This is the moose object corresponding to the ModelTemplate object
# Authors: Christopher Henry, Scott Devoid, Paul Frybarger
# Contact email: chenry@mcs.anl.gov
# Development location: Mathematics and Computer Science Division, Argonne National Lab
# Date of module creation: 2013-04-26T05:53:23
########################################################################
use strict;
use Bio::KBase::ObjectAPI::KBaseFBA::DB::ModelTemplate;
package Bio::KBase::ObjectAPI::KBaseFBA::ModelTemplate;
use Moose;
use namespace::autoclean;
use Data::Dumper;
extends 'Bio::KBase::ObjectAPI::KBaseFBA::DB::ModelTemplate';

my $cmpTranslation = {
	extracellular => "e",
    cellwall => "w",
    periplasm => "p",
    cytosol => "c",
    golgi => "g",
    endoplasm => "r",
    lysosome => "l",
    nucleus => "n",
    chloroplast => "h",
    mitochondria => "m",
    peroxisome => "x",
    vacuole => "v",
    plastid => "d",
    unknown => "u",
};

#***********************************************************************************************************
# ADDITIONAL ATTRIBUTES:
#***********************************************************************************************************
has biomassHash => ( is => 'rw', isa => 'HashRef',printOrder => '-1', type => 'msdata', metaclass => 'Typed', lazy => 1, builder => '_buildbiomassHash' );
has roleSubsystemHash => ( is => 'rw', isa => 'HashRef',printOrder => '-1', type => 'msdata', metaclass => 'Typed', lazy => 1, builder => '_buildroleSubsystemHash' );
has compoundsByAlias => ( is => 'rw', isa => 'HashRef',printOrder => '-1', type => 'msdata', metaclass => 'Typed', lazy => 1, builder => '_buildcompoundsByAlias' );
has reactionsByAlias => ( is => 'rw', isa => 'HashRef',printOrder => '-1', type => 'msdata', metaclass => 'Typed', lazy => 1, builder => '_buildreactionsByAlias' );
has roleSearchNameHash => ( is => 'rw', isa => 'HashRef',printOrder => '-1', type => 'msdata', metaclass => 'Typed', lazy => 1, builder => '_buildroleSearchNameHash' );
has biochemistry_ref => ( is => 'rw', isa => 'Str',printOrder => '-1', type => 'msdata', metaclass => 'Typed', lazy => 1, builder => '_buildbiochemistry_ref' );

#***********************************************************************************************************
# BUILDERS:
#***********************************************************************************************************
sub _buildbiochemistry_ref {
	my ($self) = @_;
	return Bio::KBase::ObjectAPI::utilities::default_biochemistry();
}
sub _buildbiomassHash {
	my ($self) = @_;
	my $biomasshash = {};
	my $bios = $self->biomasses();
	foreach my $bio (@{$bios}) {
		my $biocpds = $bio->templateBiomassComponents();
		foreach my $cpd (@{$biocpds}) {
			$biomasshash->{$cpd->templatecompcompound()->id()} = $cpd;
		}
	}
	return $biomasshash;
}
sub _buildroleSubsystemHash {
	my ($self) = @_;
	my $hash = {};
	my $sss = $self->subsystems();
	foreach my $ss (@{$sss}) {
		my $roles = $ss->roles();
		foreach my $role (@{$roles}) {
			$hash->{$role->id()}->{$ss->id()} = $ss;
		}
	}
	return $hash;
}
sub _buildcompoundsByAlias {
	my ($self) = @_;
	my $cpdhash = {};
	my $cpds = $self->compounds();
	for (my $i=0; $i < @{$cpds}; $i++) {
		my $aliases = $cpds->[$i]->aliases();
		for (my $j=0; $j < @{$aliases}; $j++) {
			my $array = [split(/:/,$aliases->[$j])];
			if (defined($array->[1])) {
				$cpdhash->{$array->[0]}->{$array->[1]}->{$cpds->[$i]->id()} = 1;
			} else {
				$cpdhash->{name}->{$array->[0]}->{$cpds->[$i]->id()} = 1;
			}
		}
	}
	return $cpdhash;
}
sub _buildreactionsByAlias {
	my ($self) = @_;
	my $rxnhash = {};
	my $rxns = $self->reactions();
	for (my $i=0; $i < @{$rxns}; $i++) {
		my $aliases = $rxns->[$i]->aliases();
		for (my $j=0; $j < @{$aliases}; $j++) {
			my $array = [split(/:/,$aliases->[$j])];
			if (defined($array->[1])) {
				$rxnhash->{$array->[0]}->{$array->[1]}->{$rxns->[$i]->id()} = 1;
			} else {
				$rxnhash->{name}->{$array->[0]}->{$rxns->[$i]->id()} = 1;
			}
		}
	}
	return $rxnhash;
}

sub _buildroleSearchNameHash {
	my ($self) = @_;
	my $rolehash = {};
	my $roles = $self->roles();
	for (my $i=0; $i < @{$roles}; $i++) {
		$rolehash->{$roles->[$i]->searchname()}->{$roles->[$i]->id()} = $roles->[$i];
		my $aliases = $roles->[$i]->aliases();
		for (my $j=0; $j < @{$aliases}; $j++) {
			$aliases->[$j] =~ s/^kegg://;
			$aliases->[$j] =~ s/^searchname://;
			my $search_alias = Bio::KBase::ObjectAPI::utilities::convertRoleToSearchRole($aliases->[$j]);
			$rolehash->{$search_alias}->{$roles->[$i]->id()} = $roles->[$i];
		}
	}
	return $rolehash;
}

#***********************************************************************************************************
# CONSTANTS:
#***********************************************************************************************************

#***********************************************************************************************************
# FUNCTIONS:
#***********************************************************************************************************
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
	my $index = $args->{compartment_index};
	my $priority = $args->{priority};
	my $cpds = $self->compcompounds();
	$self->add("compartments",{"index" => "0",
         "pH" => 7,
         "aliases" => [],
         "name" => "Periplasm",
         "id" => "p",
         "hierarchy" => 3});
	for (my $i=0; $i < @{$cpds}; $i++) {
		if 	($cpds->[$i]->id() =~ m/_$/) {
			$self->remove("compcompounds",$cpds->[$i]);
		}
	}
	$cpds = $self->compcompounds();
	for (my $i=0; $i < @{$cpds}; $i++) {
		if ($cpds->[$i]->templatecompartment()->id() eq $cmp) {
			if ($cpds->[$i]->id() =~ m/(cpd\d+)/) {
				my $msid = $1;
				$args->{hashes}->{ids}->{$msid}->{$cpds->[$i]->id().$index} = $priority;
				my $cpdhash = Bio::KBase::utilities::compound_hash();
				if (defined($cpdhash->{$msid}->{names})) {
					for (my $j=0; $j < @{$cpdhash->{$msid}->{names}}; $j++) {
						$args->{hashes}->{names}->{Bio::KBase::utilities::nameToSearchname($cpdhash->{$msid}->{names}->[$j])}->{$cpds->[$i]->id().$index} = $priority;
					}
				}
			} elsif ($cpds->[$i]->id() =~ m/(^.+)_[a-z]\d+/) {
				$args->{hashes}->{ids}->{$1}->{$cpds->[$i]->id().$index} = $priority;
			}
			if (defined($cpds->[$i]->inchikey()) && length($cpds->[$i]->inchikey()) > 0) {
				$args->{hashes}->{structures}->{$cpds->[$i]->inchikey()}->{$cpds->[$i]->id().$index} = $priority;
				my $array = [split(/[_-]/,$cpds->[$i]->inchikey())];
				$args->{hashes}->{base_structures}->{$array->[0]}->{$cpds->[$i]->id().$index} = $priority;
			}
			if (defined($cpds->[$i]->smiles()) && length($cpds->[$i]->smiles()) > 0) {
				$args->{hashes}->{structures}->{$cpds->[$i]->smiles()}->{$cpds->[$i]->id().$index} = $priority;
			}
			if (defined($cpds->[$i]->formula()) && length($cpds->[$i]->formula()) > 0) {
				$args->{hashes}->{formulas}->{$cpds->[$i]->neutral_formula()}->{$cpds->[$i]->id().$index} = $priority;
			}
			if (defined($cpds->[$i]->templatecompound()->name()) && length($cpds->[$i]->templatecompound()->name()) > 0) {
				$args->{hashes}->{names}->{Bio::KBase::utilities::nameToSearchname($cpds->[$i]->templatecompound()->name())}->{$cpds->[$i]->id().$index} = $priority;
			}
		}
	}
}

sub NewBuildModel {
	my $self = shift;
	my $args = Bio::KBase::ObjectAPI::utilities::args(["modelid"],{
		probability_threshold => 0.8,
		function_hash => {},
		reaction_hash => {},
		no_features => 0,
		use_nontemplate_reactions => 0,
		include_charge_imbalance => 0,
		include_mass_imbalance => 0,
		fulldb => 0,
		gc => 0.5,
		metagenome => undef,
		genome => undef
	}, @_);
	my $cpd_hash = Bio::KBase::utilities::new_compound_hash();
	my $rxn_hash = Bio::KBase::utilities::new_reaction_hash();
	#Creating model object
	my $mdl = Bio::KBase::ObjectAPI::KBaseFBA::FBAModel->new({
		id => $args->{modelid},
		source => Bio::KBase::utilities::conf("ModelSEED","source"),
		source_id => $args->{modelid},
		type => $self->type(),
		name => $args->{modelid},
		template_ref => $self->_reference(),
		template_refs => [$self->_reference()],
		gapfillings => [],
		gapgens => [],
		biomasses => [],
		modelcompartments => [],
		modelcompounds => [],
		modelreactions => []
	});
	#Creating attributes
	my $attributes = {
		pathways => {},
	    	auxotrophy => {},
	    fbas => {},
	    	gene_count => 0
	};
	$mdl->attributes($attributes);
	$mdl->parent($self->store());
	#Adding genome and metagenome reference
	if (defined($args->{genome})) {
		$mdl->genome_ref($args->{genome}->_reference());
		$mdl->genome($args->{genome});
		if (defined($args->{genome}->gc_content())) {
			$args->{gc} = $args->{genome}->gc_content();
		}
	}
	#print "Function hash:\n";
	#print Data::Dumper->Dump([$args->{function_hash}]);
	#print "Reaction hash:\n";
	#print Data::Dumper->Dump([$args->{reaction_hash}]);
	#Adding reactions based on input function lists
	my $rxns = $self->reactions();
	my $hash = {};
	for (my $i=0; $i < @{$rxns}; $i++) {
		my $rxn = $rxns->[$i];
		if ($rxn_hash->{$rxn->msid()}->{status} !~ m/MI/) {
			$rxn->AddRxnToModelFromAnnotations({
				probability_threshold => $args->{probability_threshold},
				function_hash => $args->{function_hash},
				reaction_hash => $args->{reaction_hash},
				model => $mdl,
				no_features => $args->{no_features},
				fulldb => $args->{fulldb}
			});
		} else {
			print $rxn->msid()."\t".$rxn_hash->{$rxn->msid()}->{status}."\n";
		}
	}
	#Adding nontemplate reactions from input reaction hash
	if ($args->{use_nontemplate_reactions} == 1 && defined($args->{reaction_hash})) {
		foreach my $rxnid (keys(%{$args->{reaction_hash}})) {
			foreach my $comp (keys(%{$args->{reaction_hash}->{$rxnid}})) {
				if ($comp eq "u") {
					$comp = "c";
				}
				my $searchid = $rxnid."_".$comp;
				if (!defined($self->getObject("reactions",$searchid))) {
					print "Attempting to add nontemplate reaction: ".$rxnid."\n";
					if (defined($rxn_hash->{$rxnid})) {
						if ($args->{include_mass_imbalance} == 1 || $rxn_hash->{$rxnid}->{status} !~ m/MI/) {
							if ($args->{include_charge_imbalance} == 1 || $rxn_hash->{$rxnid}->{status} !~ m/CI/) {
								my $data = {
									id => $searchid,
									msname => $rxn_hash->{$rxnid}->{name},
									name => $rxn_hash->{$rxnid}->{name},
									type => "conditional",
									forward_penalty => 10,
									reverse_penalty => 10,
									direction => $rxn_hash->{$rxnid}->{reversibility},
									GapfillDirection => $rxn_hash->{$rxnid}->{direction},
									maxforflux => 100,
									maxrevflux => -100,
									templatecompartment_ref => "~/compartments/id/c",
									base_cost => 10,
									templateReactionReagents => [],
									templatecomplex_refs => [],
									deltaG => 10000000.0,
		            					deltaGErr => 10000000.0,
								};
								my $rgts = [split(/;/,$rxn_hash->{$rxnid}->{stoichiometry})];
								my $allfound = 1;
								foreach my $rgt (@{$rgts}) {
									my $array = [split(/:/,$rgt)];
									my $comp = "c";
									if ($array->[2] == 1) {
										$comp = "e";
									}
									push(@{$data->{templateReactionReagents}},{
										templatecompcompound_ref => "~/compcompounds/id/".$array->[1]."_".$comp,
                    						coefficient => $array->[0]
									});
									if (!defined($self->getObject("compcompounds",$array->[1]."_".$comp))) {
										if (!defined($cpd_hash->{$array->[1]})) {
											$allfound = 0;
										} else {
											if (!defined($cpd_hash->{$array->[1]}->{formula})) {
												$cpd_hash->{$array->[1]}->{formula} = "";
											}
											if (!defined($cpd_hash->{$array->[1]}->{mass})) {
												$cpd_hash->{$array->[1]}->{mass} = 0;
											}
											if (!defined($cpd_hash->{$array->[1]}->{charge})) {
												$cpd_hash->{$array->[1]}->{charge} = 0;
											}
											if (!defined($self->getObject("compounds",$array->[1]))) {
												my $tempcpd = $self->add("compounds",{
													id => $array->[1],
													name => $cpd_hash->{$array->[1]}->{name},
													abbreviation => $cpd_hash->{$array->[1]}->{abbreviation},
													isCofactor => 0,
													aliases => $cpd_hash->{$array->[1]}->{aliases},
													defaultCharge => $cpd_hash->{$array->[1]}->{charge},
													mass => $cpd_hash->{$array->[1]}->{mass},
													deltaG => $cpd_hash->{$array->[1]}->{deltaG},
													deltaGErr => $cpd_hash->{$array->[1]}->{deltaGErr},
            											formula	=> $cpd_hash->{$array->[1]}->{formula}
												});
											}
											my $tempcompcpd = $self->add("compcompounds",{
												id => $array->[1]."_".$comp,
												templatecompound_ref => "~/compounds/id/".$array->[1],
												charge => $cpd_hash->{$array->[1]}->{charge},
												maxuptake => 0.0,
												formula => $cpd_hash->{$array->[1]}->{formula},
												templatecompartment_ref => "~/compartments/id/".$comp
											});
										}
									}
								}
								if ($allfound == 1) {
									my $temprxn = $self->add("reactions",$data);
									$temprxn->AddRxnToModelFromAnnotations({
										probability_threshold => $args->{probability_threshold},
										function_hash => $args->{function_hash},
										reaction_hash => $args->{reaction_hash},
										model => $mdl,
										no_features => $args->{no_features},
										fulldb => 0
									});
								}
							} else {
								print "Filtering out charge imbalanced reaction:".$rxnid."\n";
							}	
						} else {
							print "Filtering out mass imbalanced reaction:".$rxnid."\n";
						}
					} else {
						print "Could not find data on nontemplate reaction: ".$rxnid."\n";
					}
				}
			}
		}
	}
	#Updating charge and formula from latest biochemistry
	#my $cpds = $mdl->modelcompounds();
	#for (my $i=0; $i < @{$cpds}; $i++) {
	#	if (defined($cpd_hash->{$cpds->[$i]->msid()})) {
	#		$cpds->[$i]->charge($cpd_hash->{$cpds->[$i]->msid()}->{charge});
	#		$cpds->[$i]->formula($cpd_hash->{$cpds->[$i]->msid()}->{formula});
	#	}	
	#}
	#Adding biomass reactions
	my $bios = $self->biomasses();
	for (my $i=0; $i < @{$bios}; $i++) {
		my $bio = $bios->[$i];
 		$bio->addBioToModel({
			gc => $args->{gc},
			model => $mdl
		});
	}
	$mdl->attributes()->{gene_count} = @{$mdl->features()};
	return $mdl;
}

sub buildModel {
    my $self = shift;
	my $args = Bio::KBase::ObjectAPI::utilities::args(["genome","modelid"],{
		fulldb => 0,
	}, @_);
	my $genome = $args->{genome};
	my $mdl = Bio::KBase::ObjectAPI::KBaseFBA::FBAModel->new({
		id => $args->{modelid},
		source => Bio::KBase::utilities::conf("ModelSEED","source"),
		source_id => $args->{modelid},
		type => $self->type(),
		name => $args->{modelid},
		template_ref => $self->_reference(),
		template_refs => [$self->_reference()],
		gapfillings => [],
		gapgens => [],
		biomasses => [],
		modelcompartments => [],
		modelcompounds => [],
		modelreactions => []
	});
	$mdl->genome($genome);
	$mdl->_reference("~");
	$mdl->parent($self->parent());
	my $cds = [];
	my $genes = [];
	my $ftrs = $genome->features();
	for (my $i=0; $i < @{$ftrs}; $i++) {
		if (lc($ftrs->[$i]->type()) eq "cds") {
			push(@{$cds},$ftrs->[$i]);
		} elsif (lc($ftrs->[$i]->type()) ne "mrna") {
			push(@{$genes},$ftrs->[$i]);
		}
	}
	my $numcds = @{$cds};
	my $numgenes = @{$genes};
	if ($numcds >= 2*$numgenes) {
		$genes = $cds;
	}
	$self->extend_model_from_features({
		fulldb => $args->{fulldb},
		model => $mdl,
		features => $genes
	});
	my $bios = $self->biomasses();
	for (my $i=0; $i < @{$bios}; $i++) {
		my $bio = $bios->[$i];
		my $gc = $genome->gc_content();
		if (!defined($gc)) {
			$gc = 0.5;
		}
 		$bio->addBioToModel({
			gc => $gc,
			model => $mdl
		});
	}
	return $mdl;
}	

sub add_reactions_from_ontology_events {
	my $self = shift;
	my $args = shift;
	$args = Bio::KBase::ObjectAPI::utilities::args(["genome",],{
		fbamodel => undef,
		annotation_sources => [],
		mdl_id => $args->{genome}->id().".mdl",
		merge => 0,
		fulldb => 0
	}, $args);	
	if (@{$args->{annotation_sources}} == 0) {
		return;
	}
	if (!defined($args->{fbamodel})) {
		if (!defined($args->{mdl_id})) {
			$args->{mdl_id} = $args->{genome}->id().".mdl";
		}
		$args->{fbamodel} = Bio::KBase::ObjectAPI::KBaseFBA::FBAModel->new({
			id => $args->{mdl_id},
			source => Bio::KBase::utilities::conf("ModelSEED","source"),
			source_id => $args->{mdl_id},
			type => $self->type(),
			name => $args->{genome}->scientific_name(),
			template_ref => $self->_reference(),
			template_refs => [$self->_reference()],
			genome_ref => $args->{genome}->_reference()
		});
	}
	my $ftrs = $args->{genome}->features();
	my $rxnhash;
	my $ontology_hash = Bio::KBase::kbaseenv::get_ontology_hash();
	my $sso_hash = Bio::KBase::kbaseenv::get_sso_hash();
	my $sso_feature_role_hash = {};
	my $unmatched;
	for (my $i=0; $i < @{$ftrs}; $i++) {
		my $compartments = $ftrs->[$i]->compartments();
		my $ontterms = $ftrs->[$i]->ontology_terms();
		for (my $j=0; $j < @{$args->{annotation_sources}}; $j++) {
			if (defined($ontterms->{$args->{annotation_sources}->[$j]})) {
				my $matched = 0;
				foreach my $oid (keys(%{$ontterms->{$args->{annotation_sources}->[$j]}})) {
					if (defined($sso_hash->{$oid})) {
						$matched = 1;
						if (defined($self->roleSearchNameHash()->{$sso_hash->{$oid}->{searchname}})) {
							foreach my $roleid (keys(%{$self->roleSearchNameHash()->{$sso_hash->{$oid}->{searchname}}})) {
								if ($self->roleSearchNameHash()->{$sso_hash->{$oid}->{searchname}}->{$roleid}->source() ne "KEGG") {
									foreach my $compartment (@{$compartments}) {
										if (length($compartment) > 1 && defined($cmpTranslation->{$compartment})) {
											$compartment = $cmpTranslation->{$compartment};
										} elsif (length($compartment) > 1 && !defined($cmpTranslation->{$compartment})) {
											print STDERR "Compartment ".$compartment." not found!\n";
										}
										push(@{$sso_feature_role_hash->{$roleid}->{$compartment}},$ftrs->[$i]);
									}
								}
							}
						}
					} elsif (defined($ontology_hash->{$oid})) {
						$matched = 1;
						foreach my $rid (keys(%{$ontology_hash->{$oid}})) {
							if (defined($ontterms->{$args->{annotation_sources}->[$j]}->{$oid})) {
								$rxnhash->{$rid}->{$ftrs->[$i]->id()}->{$args->{annotation_sources}->[$j]} = 1;#$ontterms->{$args->{annotation_sources}->[$j]}->{$oid}->[0];
							}
						}
					}
				}
				if ($matched == 0) {
					$unmatched->{$ftrs->[$i]->id()} = $ontterms;
				} elsif ($args->{merge} == 1) {
					last;
				}
			}
		}
	}
	#First filling in a temporary model based on the SEED annotations
	my $tempmodel = Bio::KBase::ObjectAPI::KBaseFBA::FBAModel->new({
		id => "temp",
		source => "ModelSEED",
		source_id => "ModelSEED",
		type => "temp",
		name => "temp",
		template_ref => $self->_reference(),
		template_refs => [$self->_reference()],
		genome_ref => $args->{genome}->_reference()
	});
	$tempmodel->parent($self->parent());
	my $rxns = $self->reactions();
	for (my $i=0; $i < @{$rxns}; $i++) {
		my $rxn = $rxns->[$i];
		$rxn->addRxnToModel({
			role_features => $sso_feature_role_hash,
			model => $tempmodel,
			fulldb => $args->{fulldb},
			reaction_hash => $rxnhash
		});
	}
	#Now merging the temporary model with the existing model passed in
	my $tmdlrxns = $tempmodel->modelreactions();
	for (my $i=0; $i < @{$tmdlrxns}; $i++) {
		$args->{fbamodel}->merge_in_reaction($tmdlrxns->[$i]);
	}
}

sub extend_model_from_features {
	my $self = shift;
	my $args = Bio::KBase::ObjectAPI::utilities::args(["features","model"],{
		fulldb => 0
	}, @_);	
	my $rxns = $self->reactions();
	my $roleFeatures = {};
	my $mdl = $args->{model};
	my $features = $args->{features};
	for (my $i=0; $i < @{$features}; $i++) {
		my $ftr = $features->[$i];
		my $roles = $ftr->roles();
		my $compartments = $ftr->compartments();
		for (my $j=0; $j < @{$roles}; $j++) {
			my $role = $roles->[$j];
			for (my $k=0; $k < @{$compartments}; $k++) {
				my $abbrev = $compartments->[$k];
				if (length($compartments->[$k]) > 1 && defined($cmpTranslation->{$compartments->[$k]})) {
					$abbrev = $cmpTranslation->{$compartments->[$k]};
				} elsif (length($compartments->[$k]) > 1 && !defined($cmpTranslation->{$compartments->[$k]})) {
					print STDERR "Compartment ".$compartments->[$k]." not found!\n";
				}
				my $searchrole = Bio::KBase::ObjectAPI::utilities::convertRoleToSearchRole($role);
				if (defined($self->roleSearchNameHash()->{$searchrole})) {
					foreach my $roleid (keys(%{$self->roleSearchNameHash()->{$searchrole}})) {
						if ($self->roleSearchNameHash()->{$searchrole}->{$roleid}->source() ne "KEGG") {
							push(@{$roleFeatures->{$roleid}->{$abbrev}},$ftr);
						}
					}
				}
			}
		}
	}
	for (my $i=0; $i < @{$rxns}; $i++) {
		my $rxn = $rxns->[$i];
		$rxn->OldAddRxnToModel({
			role_features => $roleFeatures,
			model => $mdl,
			fulldb => $args->{fulldb}
		});
	}
}

=head3 searchForBiomass

Definition:
	Bio::KBase::ObjectAPI::KBaseFBA::TemplateBiomass Bio::KBase::ObjectAPI::KBaseFBA::TemplateBiomass->searchForBiomass(string:id);
Description:
	Search for biomass in template model
	
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
	Bio::KBase::ObjectAPI::KBaseFBA::TemplateReaction Bio::KBase::ObjectAPI::KBaseFBA::TemplateBiomass->searchForReaction(string:id);
Description:
	Search for reaction in template model
	
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
    } elsif ($id =~ m/^(.+)_([a-z]+)(\d*)$/) {
    	$id = $1;
    	$compartment = $2;
    	$index = $3;
    }
    if (!defined($compartment)) {
    	$compartment = "c";
    }
    if (!defined($index) || length($index) == 0) {
    	$index = 0;
    }
    return $self->queryObject("reactions",{id => $id."_".$compartment});
}

=head3 searchForCompartment
Definition:
	Bio::KBase::ObjectAPI::KBaseFBA::TemplateCompartment = Bio::KBase::ObjectAPI::KBaseFBA::TemplateCompartment->searchForCompartment(string);
Description:
	Searches for a compartment by ID, name, or alias.

=cut

sub searchForCompartment {
	my ($self,$id) = @_;
	my $cmp = $self->queryObject("compartments",{id => $id});
	#First search by exact alias match
	if (!defined($cmp)) {
		$cmp = $self->getObjectByAlias("compartments",$id);
	}
	#Next, search by name
	if (!defined($cmp)) {
		$cmp = $self->queryObject("compartments",{name => $id});
	}
	return $cmp;
}

=head3 searchForRoles
Definition:
	Bio::KBase::ObjectAPI::KBaseFBA::TemplateRole = Bio::KBase::ObjectAPI::KBaseFBA::TemplateRole->searchForRoles(string);
Description:
	Searches for a role by ID, name, or alias.

=cut

sub searchForRoles {
	my ($self,$id) = @_;
	#First search by exact alias match
	my $roleobjs = $self->getObjectsByAlias("roles",$id);
	#Next, search by name
	if (!defined($roleobjs->[0])) {
		$roleobjs = $self->queryObjects("roles",{name => $id});
	}
	if (!defined($roleobjs->[0])) {
		$roleobjs = $self->queryObjects("roles",{searchname => $id});
	}
	return $roleobjs;
}

=head3 searchForCompound
Definition:
	Bio::KBase::ObjectAPI::KBaseFBA::TemplateCompound = Bio::KBase::ObjectAPI::KBaseFBA::TemplateCompound->searchForCompound(string);
Description:
	Searches for a compound by ID, name, or alias.

=cut

sub searchForCompound {
	my ($self,$compound,$searchbio) = @_;
	#First search by exact alias match
	my $cpdobj = $self->getObject("compounds",$compound);
	#Next, search by name
	if (!defined($cpdobj)) {
		my $searchname = Bio::KBase::ObjectAPI::KBaseFBA::TemplateCompound->nameToSearchname($compound);
		$cpdobj = $self->queryObject("compounds",{searchnames => $searchname});
	}
	if (!defined($cpdobj) && defined($searchbio)) {
		$cpdobj = $self->biochemistry()->searchForCompound($compound);
		if (defined($cpdobj)) {
			$cpdobj = $self->getObject("compounds",$cpdobj->id());
		}
	}
	return $cpdobj;
}

sub checkForProton {
    my ($self) = @_;
    my $obj=$self->getObject("compounds","cpd00067");
    return $obj if $obj;
    $obj=$self->getObjectByAlias("compounds","cpd00067","ModelSEED");
    return $obj if $obj;
    $obj=$self->getObjectByAlias("compounds","C00080","KEGG");
    return $obj if $obj;
    $obj=$self->getObjectByAlias("compounds","PROTON","MetaCyc");
    return $obj if $obj;
    return $self->queryObject("compounds",{name => "H+"});
}

sub checkForWater {
    my ($self) = @_;
    my $obj=$self->getObject("compounds","cpd00001");
    return $obj if $obj;
    $obj=$self->getObjectByAlias("compounds","cpd00001","ModelSEED");
    return $obj if $obj;
    $obj=$self->getObjectByAlias("compounds","C00001","KEGG");
    return $obj if $obj;
    $obj=$self->getObjectByAlias("compounds","WATER","MetaCyc");
    return $obj if $obj;
    return $self->queryObject("compounds",{name => "Water"});
}

=head3 labelBiomassCompounds

Definition:
	void Bio::KBase::ObjectAPI::KBaseFBA::ModelTemplate->labelBiomassCompounds();
Description:
	Labels all model compounds indicating whether or not they are biomass components

=cut

sub labelBiomassCompounds {
	my $self = shift;
	for (my $i=0; $i < @{$self->compounds()}; $i++) {
		my $cpd = $self->compounds()->[$i];
		$cpd->isBiomassCompound(0);
	}
	for (my $i=0; $i < @{$self->biomasses()}; $i++) {
		my $bio = $self->biomasses()->[$i];
		for (my $j=0; $j < @{$bio->templateBiomassComponents()}; $j++) {
			my $biocpd = $bio->templateBiomassComponents()->[$j];
			$biocpd->templatecompcompound()->isBiomassCompound(1);
		}
	}
}

=head3 searchForReactionByCode
Definition:
	{rxnobj => ,dir => } = Bio::KBase::ObjectAPI::KBaseFBA::ModelTemplate::searchForReactionByCode(string);
Description:
	Searches for a reaction by its code

=cut

sub searchForReactionByCode {
	my ($self,$code) = @_;
	my $output = {dir => "f"};
	$output->{rxnobj} = $self->queryObject("reactions",{equationCode => $code});
	if (!defined($output->{rxnobj})) {
		$output->{rxnobj} = $self->queryObject("reactions",{revEquationCode => $code});
		$output->{dir} = "r";
	}
	if (!defined($output->{rxnobj})) {
		return undef;
	}
	return $output;
}

sub getObjectByAlias {
	my ($self,$attribute,$alias,$aliasName) = @_;
	my $objs = $self->getObjectsByAlias($attribute,$alias,$aliasName);
	if (defined($objs->[0])) {
        return $objs->[0];
    } else {
        return;
    }
}

sub getObjectsByAlias {
	my ($self,$attribute,$alias,$aliasName) = @_;
	my $objects = [];
	if (defined($alias)) {
		my $aliasHash;
		if ($attribute eq "compounds") {
			$aliasHash = $self->compoundsByAlias();
		} elsif ($attribute eq "reactions") {
			$aliasHash = $self->reactionsByAlias();
		}
		if (!defined($aliasName)) {
			my $uuidhash = {};
			foreach my $set (keys(%{$aliasHash})) {
				if (defined($aliasHash->{$set}->{$alias})) {
					foreach my $uuid (keys(%{$aliasHash->{$set}->{$alias}})) {
						$uuidhash->{$uuid} = 1;
					}
				}
			}
			$objects = $self->getObjects($attribute,[keys(%{$uuidhash})]);
		} else {
			my $uuidhash = {};
			if (defined($aliasHash->{$aliasName})) {
				foreach my $uuid (keys(%{$aliasHash->{$aliasName}->{$alias}})) {
					$uuidhash->{$uuid} = 1;
				}
				$objects = $self->getObjects($attribute,[keys(%{$uuidhash})]);
			}
		}
	}
	return $objects;
}

sub printTSV {
	my $self = shift;
	my $args = Bio::KBase::ObjectAPI::utilities::args([], {file => 0,path => undef,append_to => {
		compounds_table => ["id\tname\tformula\tcharge\tinchikey\tsmiles\tdeltag\tkegg id\tms id\tin model"],
		reactions_table => ["id\tdirection\tcompartment\tgpr\tname\tenzyme\tdeltag\treference\tequation\tdefinition\tms id\tbigg id\tkegg id\tkegg pathways\tmetacyc pathways\tin model"]
	},compound_filter => {},reaction_filter => {}}, @_);
	my $output = $args->{append_to};
	my $kegghash = Bio::KBase::utilities::kegg_hash();
	my $cpdhash = Bio::KBase::utilities::compound_hash();
	my $rxnhash = Bio::KBase::utilities::reaction_hash();
	my $compounds = $self->compcompounds();
	my $cpd_id_hash = {};
	my $rxn_id_hash = {};
	for (my $i=0; $i < @{$compounds}; $i++) {
		my $cpddata;
		my $msid = "";
		if (!defined($args->{compound_filter}->{$compounds->[$i]->id()."0"})) {
			if ($compounds->[$i]->id() =~ m/(cpd\d+)/ || $compounds->[$i]->compound_ref() =~ m/(cpd\d+)/) {
				$msid = $1;
				if ($msid ne "" && $msid ne "cpd00000" && defined($cpdhash->{$msid})) {
					$cpddata = $cpdhash->{$msid};
				}
			}
			my $name = $compounds->[$i]->id();
			if (defined($cpddata)) {
				$name = $cpddata->{name};
			}
			my $formula = "";
			if (defined($compounds->[$i]->formula()) && length($compounds->[$i]->formula()) > 0) {
				$formula = $compounds->[$i]->formula();
			} elsif (defined($cpddata) && defined($cpddata->{formula})) {
				$formula = $cpddata->{formula};
			}
			my $charge = "";
			if (defined($compounds->[$i]->charge()) && length($compounds->[$i]->charge()) > 0) {
				$charge = $compounds->[$i]->charge();
			} elsif (defined($cpddata)) {
				$charge = $cpddata->{charge};
			}
			my $inchikey = "";
			if (defined($cpddata) && defined($cpddata->{inchikey})) {
				$inchikey = $cpddata->{inchikey};
			}
			my $smiles = "";
			if (defined($cpddata) && defined($cpddata->{smiles})) {
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
			my $line = $compounds->[$i]->id()."0\t".$name."\t".$formula."\t".$charge."\t".$inchikey."\t".$smiles."\t".$deltag."\t".$keggid."\t".$msid."\t0";
			push(@{$output->{compounds_table}},$line);
		}
	}
	my $reactions = $self->reactions();
	for (my $i=0; $i < @{$reactions}; $i++) {
		if (!defined($args->{reaction_filter}->{$reactions->[$i]->id()."0"})) {
			my $pathway = "";
			my $reference = "";
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
			my $line = $reactions->[$i]->id()."0\t".$reactions->[$i]->direction()."\t".$reactions->[$i]->templatecompartment()->id()."\t\t".$reactions->[$i]->name()."\t".$ec."\t".$deltag."\t".$reference."\t".$equation."\t".$definition."\t".$msid."\t".$biggid."\t".$keggid."\t".$keggpath."\t".$metapath."\t0";
			push(@{$output->{reactions_table}},$line);
		}
	}
	if ($args->{file} == 1) {
		Bio::KBase::ObjectAPI::utilities::PRINTFILE($args->{path}."/".$self->id()."-compounds.tsv",$output->{compounds_table});
		Bio::KBase::ObjectAPI::utilities::PRINTFILE($args->{path}."/".$self->id()."-reactions.tsv",$output->{reactions_table});
		return [$args->{path}."/".$self->id()."-compounds.tsv",$args->{path}."/".$self->id()."-reactions.tsv"];
	}
	return $output;
}

__PACKAGE__->meta->make_immutable;
1;
