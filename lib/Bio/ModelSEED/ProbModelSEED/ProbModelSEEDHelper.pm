package Bio::ModelSEED::ProbModelSEED::ProbModelSEEDHelper;
use strict;
# Use Semantic Versioning (2.0.0-rc.1)
# http://semver.org 
our $VERSION = "0.1.0";

use Bio::P3::Workspace::WorkspaceClientExt;
use JSON::XS;
use Data::Dumper;
use Bio::KBase::ObjectAPI::utilities;
use Bio::KBase::ObjectAPI::PATRICStore;

Log::Log4perl::init($ENV{KB_SERVICE_DIR}."/log.conf");

#****************************************************************************
#Getter setters for parameters
#****************************************************************************
sub workspace_url {
	my ($self) = @_;
	return $self->{_params}->{"workspace-url"};
}
sub adminmode {
	my ($self,$adminmode) = @_;
	return $self->{_params}->{adminmode};
}

#****************************************************************************
#Workspace interaction functions
#****************************************************************************
sub save_object {
	my($self, $ref,$data,$type,$metadata) = @_;
	my $object = $self->PATRICStore()->save_object($data,$ref,$metadata,$type,1);
}
sub get_object {
	my($self, $ref,$type) = @_;
	my $object = $self->PATRICStore()->get_object($ref);
	my $meta = $self->PATRICStore()->object_meta($ref);
	if (defined($type) && $meta->[1] ne $type) {
		$self->error("Type retrieved (".$meta->[1].") does not match specified type (".$type.")!");
	}
	return $object;
}
sub get_model {
	my($self, $ref) = @_;
	my $model = $self->get_object($ref);
    if (!defined($model)) {
    	$self->error("Model retrieval failed!");
    }
	return $model;
}
sub get_genome {
	my($self, $ref) = @_;
	my $obj;
	if ($ref =~ m/^\/public\/genomes\/(.+)$/) {
		$obj = $self->retreive_reference_genome($1);
	} else {
		$obj = $self->get_object($ref);
	    if (defined($obj) && ref($obj) ne "Bio::KBase::ObjectAPI::KBaseGenomes::Genome" && defined($obj->{output_files})) {
	    	my $output = $obj->{output_files};
	    	for (my $i=0; $i < @{$obj->{output_files}}; $i++) {
	    		if ($obj->{output_files}->[$i]->[0] =~ m/\.genome$/) {
	    			$ref = $obj->{output_files}->[$i]->[0];
	    		}
	    	}
	    	$obj = $self->get_object($ref,"genome");
	    }
	}
    if (!defined($obj)) {
    	$self->error("Genome retrieval failed!");
    }
	return $obj;
}
sub get_model_meta {
	my($self, $ref) = @_;
	my $metas = $self->workspace_service()->get({
		objects => [$ref],
		metadata_only => 1,
		adminmode => $self->{_params}->{adminmode}
	});
	if (!defined($metas->[0]->[0]->[0])) {
    	return undef;
    }
	return $metas->[0]->[0];
}
sub workspace_service {
	my($self) = @_;
	if (!defined($self->{_workspace_service})) {
		$self->{_workspace_service} = Bio::P3::Workspace::WorkspaceClientExt->new($self->workspace_url(),token => $self->{_params}->{token});
	}
	return $self->{_workspace_service};
}
sub PATRICStore {
	my($self) = @_;
	if (!defined($self->{_PATRICStore})) {
		$self->{_PATRICStore} = Bio::KBase::ObjectAPI::PATRICStore->new({workspace => $self->workspace_service(),adminmode => $self->{_params}->{adminmode}});
	}
	return $self->{_PATRICStore};
}
#****************************************************************************
#Utility functions
#****************************************************************************
sub validate_args {
	my ($self,$args,$mandatoryArguments,$optionalArguments) = @_;
	return Bio::KBase::ObjectAPI::utilities::ARGS($args,$mandatoryArguments,$optionalArguments);
}
sub error {
	my($self,$msg) = @_;
	Bio::KBase::ObjectAPI::utilities::error($msg);
}
sub load_from_config {
	my($self,$msg) = @_;
	if ((my $e = $ENV{KB_DEPLOYMENT_CONFIG}) && -e $ENV{KB_DEPLOYMENT_CONFIG}) {
		my $service = $ENV{KB_SERVICE_NAME};
		if (!defined($service)) {
			$service = "ProbModelSEED";
		}
		if (defined($service)) {
			my $c = Config::Simple->new();
			$c->read($e);
			my $paramlist = [keys(%{$self->{_params}})];
			for my $p (@{$paramlist}) {
			  	my $v = $c->param("$service.$p");
			    if ($v) {
					$self->{_params}->{$p} = $v;
					if ($v eq "null") {
						$self->{_params}->{$p} = undef;
					}
			    }
			}
		}
    }
}
#****************************************************************************
#Research functions
#****************************************************************************
=head3 delete_model

Definition:
	Genome = $self->delete_model(ref Model);
Description:
	Deletes the specified model
		
=cut
sub delete_model {
	my($self,$model) = @_;
	my $metas = $self->workspace_service()->get({
		objects => [$model],
		metadata_only => 1,
		adminmode => $self->adminmode()
	});
	my $modelfolder;
	if ($model =~ m/^(.+\/)([^\/]+)$/) {
		$modelfolder = $1.".".$2;
	}
	my $output = $self->workspace_service()->delete({
		objects => [$model],
		deleteDirectories => 1,
		force => 1,
		adminmode => $self->adminmode()
	});
	push(@{$output},$self->workspace_service()->delete({
		objects => [$modelfolder],
		deleteDirectories => 1,
		force => 1,
		adminmode => $self->adminmode()
	}));
	return $output;
}

=head3 classify_genome

Definition:
	Genome = $self->classify_genome(string classifier,Genome genome);
Description:
	Returns the cell wall classification for genome
		
=cut
sub classify_genome {
	my($self,$classifier,$genome) = @_;
	my $data = [split(/\n/,$classifier)];
    my $headings = [split(/\t/,$data->[0])];
	my $popprob = [split(/\t/,$data->[1])];
	my $classdata = {};
	for (my $i=1; $i < @{$headings}; $i++) {
		$classdata->{classifierClassifications}->{$headings->[$i]} = {
			name => $headings->[$i],
			populationProbability => $popprob->[$i]
		};
	}
	my $cfRoleHash = {};
	for (my $i=2;$i < @{$data}; $i++) {
		my $row = [split(/\t/,$data->[$i])];
		my $searchrole = Bio::KBase::ObjectAPI::utilities::convertRoleToSearchRole($row->[0]);
		$classdata->{classifierRoles}->{$searchrole} = {
			classificationProbabilities => {},
			role => $row->[0]
		};
		for (my $j=1; $j < @{$headings}; $j++) {
			$classdata->{classifierRoles}->{$searchrole}->{classificationProbabilities}->{$headings->[$j]} = $row->[$j];
		}
	}
	my $scores = {};
	my $sum = 0;
	foreach my $class (keys(%{$classdata->{classifierClassifications}})) {
		$scores->{$class} = 0;
		$sum += $classdata->{classifierClassifications}->{$class}->{populationProbability};
	}
	my $genes = $genome->features();
	foreach my $gene (@{$genes}) {
		my $roles = $gene->roles();
		foreach my $role (@{$roles}) {
			my $searchrole = Bio::KBase::ObjectAPI::utilities::convertRoleToSearchRole($role);
			if (defined($classdata->{classifierRoles}->{$searchrole})) {
				foreach my $class (keys(%{$classdata->{classifierClassifications}})) {
					$scores->{$class} += $classdata->{classifierRoles}->{$searchrole}->{classificationProbabilities}->{$class};
				}
			}
		}
	}
	my $largest;
	my $largestClass;
	foreach my $class (keys(%{$classdata->{classifierClassifications}})) {
		$scores->{$class} += log($classdata->{classifierClassifications}->{$class}->{populationProbability}/$sum);
		if (!defined($largest)) {
			$largest = $scores->{$class};
			$largestClass = $class;
		} elsif ($largest > $scores->{$class}) {
			$largest = $scores->{$class};
			$largestClass = $class;
		}
	}
	return $largestClass;
}
=head3 retreive_reference_genome

Definition:
	Genome = $self->retreive_reference_genome(string genome);
Description:
	Returns typed object for genome in PATRIC reference database
		
=cut
sub retreive_reference_genome {
	my($self, $genome) = @_;
	my $gto = {
		
	};
	return $gto;
}
=head3 build_fba_object

Definition:
	Genome = $self->build_fba_object({} params);
Description:
	Returns typed object for FBA
		
=cut
sub build_fba_object {
	my($self,$model,$params) = @_;
	my $media = $self->get_object($params->{media},"media");
    if (!defined($media)) {
    	$self->error("Media retrieval failed!");
    }
    my $simptherm = 0;
    my $thermconst = 0;
    if ($params->{thermo_const_type} eq "Simple") {
    	$simptherm = 1;
    	$thermconst = 1;
    }
    my $fba = Bio::KBase::ObjectAPI::KBaseFBA::FBA->new({
		id => $params->{output_file},
		fva => $params->{fva},
		fluxMinimization => $params->{minimizeflux},
		findMinimalMedia => $params->{findminmedia},
		allReversible => $params->{allreversible},
		simpleThermoConstraints => $simptherm,
		thermodynamicConstraints => $thermconst,
		noErrorThermodynamicConstraints => 0,
		minimizeErrorThermodynamicConstraints => 1,
		maximizeObjective => 1,
		compoundflux_objterms => {},
    	reactionflux_objterms => {},
		biomassflux_objterms => {},
		comboDeletions => 0,
		numberOfSolutions => 1,
		objectiveConstraintFraction => $params->{objective_fraction},
		defaultMaxFlux => 1000,
		defaultMaxDrainFlux => 0,
		defaultMinDrainFlux => -1000,
		decomposeReversibleFlux => 0,
		decomposeReversibleDrainFlux => 0,
		fluxUseVariables => 0,
		drainfluxUseVariables => 0,
		fbamodel_ref => $model->_reference(),
		media_ref => $media->_reference(),
		geneKO_refs => [],
		reactionKO_refs => [],
		additionalCpd_refs => [],
		uptakeLimits => {},
		parameters => {},
		inputfiles => {},
		FBAConstraints => [],
		FBAReactionBounds => [],
		FBACompoundBounds => [],
		outputfiles => {},
		FBACompoundVariables => [],
		FBAReactionVariables => [],
		FBABiomassVariables => [],
		FBAPromResults => [],
		FBADeletionResults => [],
		FBAMinimalMediaResults => [],
		FBAMetaboliteProductionResults => [],
	});
	$fba->parent($self->PATRICStore());
	foreach my $term (@{$params->{objective}}) {
		if ($term->[0] eq "flux" || $term->[0] eq "reactionflux") {
			$term->[0] = "flux";
			my $obj = $model->searchForReaction($term->[1]);
			if (!defined($obj)) {
				$self->_error("Reaction ".$term->[1]." not found!");
			}
			$fba->reactionflux_objterms()->{$obj->id()} = $term->[2];
		} elsif ($term->[0] eq "compoundflux" || $term->[0] eq "drainflux") {
			$term->[0] = "drainflux";
			my $obj = $model->searchForCompound($term->[1]);
			if (!defined($obj)) {
				$self->_error("Compound ".$term->[1]." not found!");
			}
			$fba->compoundflux_objterms()->{$obj->id()} = $term->[2];
		} elsif ($term->[0] eq "biomassflux") {
			my $obj = $model->searchForBiomass($term->[1]);
			if (!defined($obj)) {
				$self->_error("Biomass ".$term->[1]." not found!");
			}
			$fba->biomassflux_objterms()->{$obj->id()} = $term->[2];
		} else {
			$self->_error("Objective variable type ".$term->[0]." not recognized!");
		}
	}
	foreach my $term (@{$params->{custom_bounds}}) {
		if ($term->[0] eq "flux" || $term->[0] eq "reactionflux") {
			$term->[0] = "flux";
			my $obj = $model->searchForReaction($term->[1]);
			if (!defined($obj)) {
				$self->_error("Reaction ".$term->[1]." not found!");
			}
			$fba->add("FBAReactionBounds",{modelreaction_ref => $obj->_reference(),variableType=> $term->[0],upperBound => $term->[2],lowerBound => $term->[3]});
		} elsif ($term->[0] eq "compoundflux" || $term->[0] eq "drainflux") {
			$term->[0] = "flux";
			my $obj = $model->searchForCompound($term->[1]);
			if (!defined($obj)) {
				$self->_error("Compound ".$term->[1]." not found!");
			}
			$fba->add("FBACompoundBounds",{modelcompound_ref => $obj->_reference(),variableType=> $term->[0],upperBound => $term->[2],lowerBound => $term->[3]});
		} else {
			$self->_error("Objective variable type ".$term->[0]." not recognized!");
		}
	}
	if (defined($model->genome_ref())) {
		my $genome = $model->genome();
		foreach my $gene (@{$params->{geneko}}) {
			my $geneObj = $genome->searchForFeature($gene);
			if (defined($geneObj)) {
				$fba->addLinkArrayItem("geneKOs",$geneObj);
			}
		}
	}
	foreach my $reaction (@{$params->{rxnko}}) {
		my $rxnObj = $model->searchForReaction($reaction);
		if (defined($rxnObj)) {
			$fba->addLinkArrayItem("reactionKOs",$rxnObj);
		}
	}
	foreach my $compound (@{$params->{media_supplement}}) {
		my $cpdObj = $model->searchForCompound($compound);
		if (defined($cpdObj)) {
			$fba->addLinkArrayItem("additionalCpds",$cpdObj);
		}
	}
	return $fba;
}
#****************************************************************************
#Apps
#****************************************************************************
sub ModelReconstruction {
	my($self,$parameters) = @_;
    my $starttime = time();
    if (defined($parameters->{adminmode})) {
    	$self->{_params}->{adminmode} = $parameters->{adminmode}
    }
    $parameters = $self->validate_args($parameters,[],{
    	template_model => undef,
    	fulldb => 0,
    	output_path => "/".$self->{_params}->{username}."/models/",
    	genome => undef,
    	output_file => undef
    });

	my $log = Log::Log4perl->get_logger("ProbModelSEEDHelper");
    $log->info("Started model reconstruction for genome ".$parameters->{genome});

  	my $genome = $self->get_genome($parameters->{genome});
    if (!defined($parameters->{output_file})) {
    	$parameters->{output_file} = $genome->id()."_model";	
    }
    my $template;
    if (!defined($parameters->{templatemodel})) {
    	if ($genome->domain() eq "Plant" || $genome->taxonomy() =~ /viridiplantae/i) {
    		$template = $self->get_object("/chenry/public/modelsupport/templates/plant.modeltemplate","modeltemplate");
    	} else {
    		my $classifier_data = $self->get_object("/chenry/public/modelsupport/classifiers/gramclassifier.string","string");
    		my $class = $self->classify_genome($classifier_data,$genome);
    		if ($class eq "Gram positive") {
	    		$template = $self->get_object("/chenry/public/modelsupport/templates/GramPositive.modeltemplate","modeltemplate");
	    	} elsif ($class eq "Gram negative") {
	    		$template = $self->get_object("/chenry/public/modelsupport/templates/GramNegative.modeltemplate","modeltemplate");
	    	}
    	}
    } else {
    	$template = $self->get_object($parameters->{templatemodel},"modeltemplate");
    }
    if (!defined($template)) {
    	$self->error("template retrieval failed!");
    }
    my $mdl = $template->buildModel({
	    genome => $genome,
	    modelid => $parameters->{output_file},
	    fulldb => $parameters->{fulldb}
	});
	my $folder = $parameters->{output_path}."/.".$parameters->{output_file};
    my $outputfiles = [];
    if ($self->{_params}->{run_as_app} == 0) {
    	$self->save_object($folder,undef,"folder",{application_type => "ModelReconstruction"});
    } else {
    	$self->{_params}->{app}->create_result_folder();
    }
    $mdl->jobresult({
    	id => 0,
		app => {
			"id"=>"ModelReconstruction",
			"script"=>"App-ModelReconstruction",
			"label"=>"Reconstruct metabolic model",
			"description"=>"Reconstructs a metabolic model from an annotated genome.",
			"parameters"=>[]
		},
		parameters => $parameters,
		start_time => $starttime,
		end_time => time(),
		elapsed_time => time()-$starttime,
		output_files => [[$parameters->{output_path}."/".$parameters->{output_file}]],
		job_output => "",
		hostname => "https://p3.theseed.org/services/ProbModelSEED"
    });
    $self->save_object($folder."/fba",undef,"folder");
    $self->save_object($folder."/gapfilling",undef,"folder");
    return $self->save_object($parameters->{output_path}."/".$parameters->{output_file},$mdl,"model");
}

sub FluxBalanceAnalysis {
	my($self,$parameters) = @_;
    my $starttime = time();
    if (defined($parameters->{adminmode})) {
    	$self->{_params}->{adminmode} = $parameters->{adminmode}
    }
	$parameters = $self->validate_args($parameters,["model"],{
		media => "/chenry/public/modelsupport/media/Complete",
		fva => 0,
		predict_essentiality => 0,
		minimizeflux => 0,
		findminmedia => 0,
		allreversible => 0,
		thermo_const_type => "None",
		media_supplement => [],
		geneko => [],
		rxnko => [],
		objective_fraction => 1,
		custom_bounds => [],
		objective => [["biomassflux","bio1",1]],
		custom_constraints => [],
		uptake_limits => [],
	});

	my $log = Log::Log4perl->get_logger("ProbModelSEEDHelper");
    $log->info("Started flux balance analysis for model ".$parameters->{model}." on media ".$parameters->{media});

    my $model = $self->get_model($parameters->{model});
    $parameters->{model} = $model->_reference();
    
    #Setting output path based on model and then creating results folder
    $parameters->{output_path} = $model->wsmeta()->[2].".".$model->wsmeta()->[0]."/fba";
    if (!defined($parameters->{output_file})) {
	    my $list = $self->workspace_service()->ls({
			paths => [$parameters->{output_path}],
			excludeDirectories => 1,
			excludeObjects => 0,
			recursive => 1,
			query => {type => "fba"}
		});
		my $index = 0;
		if (defined($list->{$parameters->{output_path}})) {
			$list = $list->{$parameters->{output_path}};
			$index = @{$list};
			for (my $i=0; $i < @{$list}; $i++) {
				if ($list->[$i]->[0] =~ /^fba\.(\d+)$/) {
					if ($1 > $index) {
						$index = $1+1;
					}
				}
			}
		}
		$parameters->{output_file} = "fba.".$index;
    }
    
    my $fba = $self->build_fba_object($model,$parameters);
    my $objective = $fba->runFBA();
    if (!defined($objective)) {
    	$self->error("FBA failed with no solution returned! See ".$fba->jobnode());
    }
    $fba->jobresult({
    	id => 0,
		app => {
			"id"=>"FluxBalanceAnalysis",
			"script"=>"App-FluxBalanceAnalysis",
			"label"=>"Run flux balance analysis",
			"description"=>"Run flux balance analysis on model.",
			"parameters"=>[]
		},
		parameters => $parameters,
		start_time => $starttime,
		end_time => time(),
		elapsed_time => time()-$starttime,
		output_files => [[ $parameters->{output_path}."/".$parameters->{output_file}]],
		job_output => "",
		hostname => "https://p3.theseed.org/services/ProbModelSEED",
    });
    return $self->save_object($parameters->{output_path}."/".$parameters->{output_file},$fba,"fba",{
    	objective => $objective,
    	media => $parameters->{media}
    });
}

sub GapfillModel {
	my($self,$parameters) = @_;
	my $starttime = time();
    if (defined($parameters->{adminmode})) {
    	$self->{_params}->{adminmode} = $parameters->{adminmode}
    }
    $parameters = $self->validate_args($parameters,["model"],{
		media => "/chenry/public/modelsupport/media/Complete",
		probanno => undef,
		alpha => 0,
		allreversible => 0,
		thermo_const_type => "None",
		media_supplement => [],
		geneko => [],
		rxnko => [],
		objective_fraction => 0.001,
		uptake_limits => [],
		custom_bounds => [],
		objective => [["biomassflux","bio1",1]],
		custom_constraints => [],
		low_expression_theshold => 0.5,
		high_expression_theshold => 0.5,
		target_reactions => [],
		completeGapfill => 0,
		solver => undef,
		omega => 0,
		allowunbalanced => 0,
		blacklistedrxns => [],
		gauranteedrxns => [],
		exp_raw_data => {},
		source_model => undef,
		integrate_solution => 0,
	});
	my $log = Log::Log4perl->get_logger("ProbModelSEEDHelper");
    $log->info("Starting gap fill for model ".$parameters->{model}." on media ".$parameters->{media});
	
    if (defined($parameters->{adminmode}) && $parameters->{adminmode} == 1) {
    	$self->admin_mode($parameters->{adminmode});
    }
    my $model = $self->get_model($parameters->{model});
    $parameters->{model} = $model->_reference();
    
    #Setting output path based on model and then creating results folder
    $parameters->{output_path} = $model->wsmeta()->[2].".".$model->wsmeta()->[0]."/gapfilling";
    if (!defined($parameters->{output_file})) {
	    my $gflist = $self->workspace_service()->ls({
			paths => [$parameters->{output_path}],
			excludeDirectories => 1,
			excludeObjects => 0,
			recursive => 1,
			query => {type => "fba"}
		});
		my $index = 0;
		if (defined($gflist->{$parameters->{output_path}})) {
			$gflist = $gflist->{$parameters->{output_path}};
			$index = @{$gflist};
			for (my $i=0; $i < @{$gflist}; $i++) {
				if ($gflist->[$i]->[0] =~ /^gf\.(\d+)$/) {
					if ($1 > $index) {
						$index = $1+1;
					}
				}
			}
		}
		$parameters->{output_file} = "gf.".$index;
    }
    Bio::KBase::ObjectAPI::utilities::set_global("gapfill name",$parameters->{output_file});
    
    if (defined($parameters->{source_model})) {
		$parameters->{source_model} = $self->get_model($parameters->{source_model});
    }
    
    my $fba = $self->build_fba_object($model,$parameters);
    $fba->PrepareForGapfilling($parameters);
    my $objective = $fba->runFBA();
    $fba->parseGapfillingOutput();
    if (!defined($fba->gapfillingSolutions()->[0])) {
		$self->error("Analysis completed, but no valid solutions found!");
	}
	if (@{$fba->gapfillingSolutions()->[0]->gapfillingSolutionReactions()} == 0) {
		$self->error("No gapfilling needed on specified condition!");
	}
	my $gfsols = [];
	for (my $i=0; $i < @{$fba->gapfillingSolutions()}; $i++) {
		for (my $j=0; $j < @{$fba->gapfillingSolutions()->[$i]->gapfillingSolutionReactions()}; $j++) {
			$gfsols->[$i]->[$j] = $fba->gapfillingSolutions()->[$i]->gapfillingSolutionReactions()->[$j]->serializeToDB();
		}
	}
	my $solutiondata = Bio::KBase::ObjectAPI::utilities::TOJSON($gfsols);
	$fba->jobresult({
    	id => 0,
		app => {
			"id"=>"GapfillModel",
			"script"=>"App-GapfillModel",
			"label"=>"Gapfill metabolic model",
			"description"=>"Run gapfilling on model.",
			"parameters"=>[]
		},
		parameters => $parameters,
		start_time => $starttime,
		end_time => time(),
		elapsed_time => time()-$starttime,
		output_files => [[ $parameters->{output_path}."/".$parameters->{output_file}]],
		job_output => "",
		hostname => "https://p3.theseed.org/services/ProbModelSEED",
    });
	return $self->save_object($parameters->{output_path}."/".$parameters->{output_file},$fba,"fba",{
		integrated_solution => 0,
		solutiondata => $solutiondata,
		integratedindex => 0,
		media => $parameters->{media},
		integrated => $parameters->{integrate_solution}
	});
}

#****************************************************************************
#Constructor
#****************************************************************************
sub new {
    my($class, $parameters) = @_;
    my $self = {};
    bless $self, $class;
    $parameters = $self->validate_args($parameters,["token","username",],{
    	fbajobcache => "",
    	fbajobdir => "",
    	mfatoolkitbin => "",
    	"workspace-url" => "http://p3.theseed.org/services/Workspace",
    	adminmode => 0,
    	method => "unknown",
    	run_as_app => 0
    });
    $self->{_params} = $parameters;
    return $self;
}

1;
