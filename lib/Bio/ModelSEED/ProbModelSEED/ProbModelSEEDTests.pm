{
	package Bio::ModelSEED::ProbModelSEED::ProbModelSEEDTests;
	
	use strict;
	use Test::More;
	use Data::Dumper;
	
	sub new {
	    my($class,$auth,$url,$dump,$config) = @_;
	    my $self = {
			testcount => 0,
			dumpoutput => 0,
			auth => $auth,
			url => $url
	    };
	    $ENV{KB_INTERACTIVE} = 1;
	    if (defined($config)) {
	    	$ENV{KB_DEPLOYMENT_CONFIG} = $config;
	    }
	    if (defined($dump)) {
	    	$self->{dumpoutput} = $dump;
	    }
	    if (!defined($url) || $url eq "impl") {
	    	print "Loading server with this config: ".$ENV{KB_DEPLOYMENT_CONFIG}."\n";
	    	require "Bio/ModelSEED/ProbModelSEED/ProbModelSEEDImpl.pm";
	    	$Bio::ModelSEED::ProbModelSEED::Service::CallContext = Bio::ModelSEED::ProbModelSEED::Service::CallContext->new($auth->[0]->{token},"test",$auth->[0]->{username});
	    	$self->{obj} = Bio::ModelSEED::ProbModelSEED::ProbModelSEEDImpl->new();
	    } else {
	    	require "Bio/ModelSEED/ProbModelSEED/ProbModelSEEDClient.pm";
	    	$self->{obj} = Bio::ModelSEED::ProbModelSEED::ProbModelSEEDClient->new($url,token => $auth->[0]->{token});
	    }
	    return bless $self, $class;
	}
	
	sub test_harness {
		my($self,$function,$parameters) = @_;
		my $output;
		if (defined($parameters)) {
			$output = $self->{obj}->$function($parameters);
		} else {
			$output = $self->{obj}->$function();
		}
		ok defined($output), "Successfully ran $function!";
		if ($self->{dumpoutput}) {
			print "$function output:\n".Data::Dumper->Dump([$output])."\n\n";
		}
		$self->{testcount}++;
		return $output;
	}
	
	sub run_tests {
		my($self) = @_;
		my $output = $self->test_harness("list_models",undef);
		for(my $i=0; $i < @{$output}; $i++) {
			if ($output->[$i] eq "/chenry/models/TestModel") {
				my $output = $self->test_harness("delete_model",{
					model => "/chenry/models/TestModel",
				});
			}
		}
		$output = $self->test_harness("ModelReconstruction",{
			genome => "/chenry/genomes/test/.Buchnera_aphidicola/Buchnera_aphidicola.genome",
			fulldb => "0",
			output_path => "/chenry/models",
			output_file => "TestModel"
		});
		$output = $self->test_harness("list_models",undef);
		$output = $self->test_harness("GapfillModel",{
			model => "/chenry/models/TestModel",
			integrate_solution => "1"
		});
		$output = $self->test_harness("GapfillModel",{
			model => "/chenry/models/TestModel",
			integrate_solution => "1",
			media => "/chenry/public/modelsupport/media/Carbon-D-Glucose"
		});
		$output = $self->test_harness("FluxBalanceAnalysis",{
			model => "/chenry/models/TestModel",
		});
		$output = $self->test_harness("FluxBalanceAnalysis",{
			model => "/chenry/models/TestModel",
			media => "/chenry/public/modelsupport/media/Carbon-D-Glucose"
		});
		$output = $self->test_harness("list_gapfill_solutions",{
			model => "/chenry/models/TestModel"
		});
		$output = $self->test_harness("manage_gapfill_solutions",{
			model => "/chenry/models/TestModel",
			commands => {
				testgapfill => "u"
			}
		});
		$output = $self->test_harness("manage_gapfill_solutions",{
			model => "/chenry/models/TestModel",
			commands => {
				testgapfill => "i"
			}
		});
		$output = $self->test_harness("manage_gapfill_solutions",{
			model => "/chenry/models/TestModel",
			commands => {
				testgapfill => "d"
			}
		});
		$output = $self->test_harness("list_fba_studies",{
			model => "/chenry/models/TestModel"
		});
		$output = $self->test_harness("delete_fba_studies",{
			model => "/chenry/models/TestModel",
			fbas => ["testfba"]
		});
		done_testing($self->{testcount});
	}
}	

{
	package Bio::ModelSEED::ProbModelSEED::Service::CallContext;
	
	use strict;
	
	sub new {
	    my($class,$token,$method,$user) = @_;
	    my $self = {
	        token => $token,
	        method => $method,
	        user_id => $user
	    };
	    return bless $self, $class;
	}
	sub user_id {
		my($self) = @_;
		return $self->{user_id};
	}
	sub token {
		my($self) = @_;
		return $self->{token};
	}
	sub method {
		my($self) = @_;
		return $self->{method};
	}
}

1;