package Bio::ModelSEED::ProbModelSEED::ProbModelSEEDImpl;
use strict;
use Bio::KBase::Exceptions;
# Use Semantic Versioning (2.0.0-rc.1)
# http://semver.org 
our $VERSION = "0.1.0";

=head1 NAME

ProbModelSEED

=head1 DESCRIPTION

=head1 ProbModelSEED

=cut

#BEGIN_HEADER

use File::Path;
use File::Copy ("cp","mv");
use File::stat;
use Fcntl ':mode';
use Data::UUID;
use REST::Client;
use Bio::P3::Workspace::WorkspaceClient;
use JSON::XS;
use Data::Dumper;
use HTTP::Request::Common;
use Log::Log4perl qw(:easy);
use MongoDB::Connection;
use URI::Escape;
use AnyEvent;
use AnyEvent::HTTP;
use Config::Simple;
use Plack::Request;
use Bio::ModelSEED::Exceptions;

Log::Log4perl->easy_init($DEBUG);

#
# Alias our context variable.
#
*Bio::ModelSEED::ProbModelSEED::ProbModelSEEDImpl::CallContext = *Bio::ModelSEED::ProbModelSEED::Service::CallContext;
our $CallContext;

#Returns the authentication token supplied to the service in the context object
sub authentication {
	my($self) = @_;
	return $CallContext->token;
}

#Returns the username supplied to the service in the context object
sub getUsername {
	my ($self) = @_;
	return $CallContext->user_id;
}

#Initialization function for call
sub initialize_call {
	my ($self,$params) = @_;
	#Setting URL for connected services
	if (defined($params->{adminmode})) {
		$self->helper()->admin_mode($params->{adminmode});
	}
	if (defined($params->{wsurl})) {
		$self->helper()->workspace_url($params->{wsurl});
	}
    Bio::ModelSEED::ProbModelSEED::utilities::token($self->_authentication());
	return $params;
}

#Returns the method supplied to the service in the context object
sub current_method {
	my ($self) = @_;
	return $CallContext->method;
}

sub config {
	my ($self) = @_;
	return $self->{_config};
}

sub helper {
	my ($self) = @_;
	if (!defined($self->{_helper})) {
		$CallContext->{_helper} = Bio::ModelSEED::ProbModelSEED::ProbModelSEEDHelper->new($self->config());
	}
	return $CallContext->{_helper};
}

sub _list_fba_studies {
	my ($self,$input) = @_;
	$input = $self->helper()->validate_args($input,["model"],{});
    $input->{model_obj} = $self->helper()->get_model($input->{model});
    my $list = $self->helper()->workspace_service()->ls({
		paths => [$input->{model_obj}->wsmeta()->[2]."fba"],
		excludeDirectories => 1,
		excludeObjects => 0,
		recursive => 1,
		query => {type => "fba"}
	});
	my $output = {};
	for (my $i=0; $i < @{$list}; $i++) {
		$output->{$list->[$i]->[0]} = {
			rundate => $list->[$i]->[3],
			id => $list->[$i]->[0],
			fba => $list->[$i]->[2].$list->[$i]->[0],
			media => $list->[$i]->[7]->{media},
			objective => $list->[$i]->[7]->{objective},
			objective_function => $list->[$i]->[7]->{objective_function},
		};
	}
	return $output;
}

sub _list_gapfill_studies {
	my ($self,$input) = @_;
	$input = $self->helper()->validate_args($input,["model"],{});
    $input->{model_obj} = $self->helper()->get_model($input->{model});
    my $gflist = $self->helper()->workspace_service()->ls({
		paths => [$model->wsmeta()->[2]."gapfilling"],
		excludeDirectories => 1,
		excludeObjects => 0,
		recursive => 1,
		query => {type => "fba"}
	});
	$output = {};
	for (my $i=0; $i < @{$gflist}; $i++) {
		$output->{$gflist->[$i]->[0]} = {
			rundate => $gflist->[$i]->[3],
			id => $gflist->[$i]->[0],
			gapfill => $gflist->[$i]->[2].$gflist->[$i]->[0],
			media => $gflist->[$i]->[7]->{media},
			integrated => $gflist->[$i]->[7]->{media},
			integrated_solution => $gflist->[$i]->[7]->{media},
			solution_reactions => []
		};
	}
	return $output;
}

sub _list_model_edits {
	my ($self,$input) = @_;
	$input = $self->helper()->validate_args($input,["model"],{});
    $input->{model_obj} = $self->helper()->get_model($input->{model});
    my $list = $self->helper()->workspace_service()->ls({
		paths => [$input->{model_obj}->wsmeta()->[2]."edits"],
		excludeDirectories => 1,
		excludeObjects => 0,
		recursive => 1,
		query => {type => "model_edit"}
	});
	my $output = {};
	for (my $i=0; $i < @{$list}; $i++) {
		my $data = Bio::KBase::ObjectAPI::utilities::FROMJSON($list->[$i]->[7]->{editdata});
		$output->{$list->[$i]->[0]} = {
			rundate => $list->[$i]->[3],
			integrated => $list->[$i]->[7]->{integrated},
			id => $list->[$i]->[0],
			edit => $list->[$i]->[2].$list->[$i]->[0],
			reactions_to_delete => $data->{reactions_to_delete},
			altered_directions => $data->{altered_directions},
			altered_gpr => $data->{altered_gpr},
			reactions_to_add => $data->{reactions_to_add},
			altered_biomass_compound => $data->{altered_biomass_compound}
		};
	}
	return $output;
}

#END_HEADER

sub new
{
    my($class, @args) = @_;
    my $self = {
    };
    bless $self, $class;
    #BEGIN_CONSTRUCTOR
    my $params = $args[0];
    my $helper = Bio::ModelSEED::ProbModelSEED::ProbModelSEEDHelper->new($params);
    $self->{_config} = $helper->{_params};
    #END_CONSTRUCTOR

    if ($self->can('_init_instance'))
    {
	$self->_init_instance();
    }
    return $self;
}

=head1 METHODS



=head2 list_gapfill_solutions

  $output = $obj->list_gapfill_solutions($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a list_gapfill_solutions_params
$output is a reference to a hash where the key is a gapfill_id and the value is a gapfill_data
list_gapfill_solutions_params is a reference to a hash where the following keys are defined:
	model has a value which is a ref
ref is a string
gapfill_id is a string
gapfill_data is a reference to a hash where the following keys are defined:
	rundate has a value which is a timestamp
	id has a value which is a gapfill_id
	gapfill has a value which is a ref
	media has a value which is a ref
	integrated has a value which is a bool
	integrated_solution has a value which is an int
	solution_reactions has a value which is a reference to a list where each element is a reference to a list where each element is a gapfill_reaction
timestamp is a string
bool is an int
gapfill_reaction is a reference to a hash where the following keys are defined:
	reaction has a value which is a ref
	direction has a value which is a reaction_direction
	compartment has a value which is a string
reaction_direction is a string

</pre>

=end html

=begin text

$input is a list_gapfill_solutions_params
$output is a reference to a hash where the key is a gapfill_id and the value is a gapfill_data
list_gapfill_solutions_params is a reference to a hash where the following keys are defined:
	model has a value which is a ref
ref is a string
gapfill_id is a string
gapfill_data is a reference to a hash where the following keys are defined:
	rundate has a value which is a timestamp
	id has a value which is a gapfill_id
	gapfill has a value which is a ref
	media has a value which is a ref
	integrated has a value which is a bool
	integrated_solution has a value which is an int
	solution_reactions has a value which is a reference to a list where each element is a reference to a list where each element is a gapfill_reaction
timestamp is a string
bool is an int
gapfill_reaction is a reference to a hash where the following keys are defined:
	reaction has a value which is a ref
	direction has a value which is a reaction_direction
	compartment has a value which is a string
reaction_direction is a string


=end text



=item Description



=back

=cut

sub list_gapfill_solutions
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_gapfill_solutions:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_gapfill_solutions');
    }

    my $ctx = $Bio::ModelSEED::ProbModelSEED::Service::CallContext;
    my($output);
    #BEGIN list_gapfill_solutions
    $input = $self->initialize_call($input);
    $input = $self->helper()->validate_args($input,["model"],{});
	$output = $self->_list_gapfill_studies($input);
    #END list_gapfill_solutions
    my @_bad_returns;
    (ref($output) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_gapfill_solutions:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_gapfill_solutions');
    }
    return($output);
}




=head2 manage_gapfill_solutions

  $output = $obj->manage_gapfill_solutions($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a manage_gapfill_solutions_params
$output is a reference to a hash where the key is a gapfill_id and the value is a gapfill_data
manage_gapfill_solutions_params is a reference to a hash where the following keys are defined:
	model has a value which is a ref
	commands has a value which is a reference to a hash where the key is a gapfill_id and the value is a gapfill_command
	selected_solutions has a value which is a reference to a hash where the key is a gapfill_id and the value is an int
ref is a string
gapfill_id is a string
gapfill_command is a string
gapfill_data is a reference to a hash where the following keys are defined:
	rundate has a value which is a timestamp
	id has a value which is a gapfill_id
	gapfill has a value which is a ref
	media has a value which is a ref
	integrated has a value which is a bool
	integrated_solution has a value which is an int
	solution_reactions has a value which is a reference to a list where each element is a reference to a list where each element is a gapfill_reaction
timestamp is a string
bool is an int
gapfill_reaction is a reference to a hash where the following keys are defined:
	reaction has a value which is a ref
	direction has a value which is a reaction_direction
	compartment has a value which is a string
reaction_direction is a string

</pre>

=end html

=begin text

$input is a manage_gapfill_solutions_params
$output is a reference to a hash where the key is a gapfill_id and the value is a gapfill_data
manage_gapfill_solutions_params is a reference to a hash where the following keys are defined:
	model has a value which is a ref
	commands has a value which is a reference to a hash where the key is a gapfill_id and the value is a gapfill_command
	selected_solutions has a value which is a reference to a hash where the key is a gapfill_id and the value is an int
ref is a string
gapfill_id is a string
gapfill_command is a string
gapfill_data is a reference to a hash where the following keys are defined:
	rundate has a value which is a timestamp
	id has a value which is a gapfill_id
	gapfill has a value which is a ref
	media has a value which is a ref
	integrated has a value which is a bool
	integrated_solution has a value which is an int
	solution_reactions has a value which is a reference to a list where each element is a reference to a list where each element is a gapfill_reaction
timestamp is a string
bool is an int
gapfill_reaction is a reference to a hash where the following keys are defined:
	reaction has a value which is a ref
	direction has a value which is a reaction_direction
	compartment has a value which is a string
reaction_direction is a string


=end text



=item Description



=back

=cut

sub manage_gapfill_solutions
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to manage_gapfill_solutions:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'manage_gapfill_solutions');
    }

    my $ctx = $Bio::ModelSEED::ProbModelSEED::Service::CallContext;
    my($output);
    #BEGIN manage_gapfill_solutions
    $input = $self->initialize_call($input);
    $input = $self->helper()->validate_args($input,["model","commands"],{
    	selected_solutions => {}
    });
    my $gflist = $self->_list_gapfill_studies($input);
    my $rmlist = [];
    my $updatelist = [];
    foreach my $gf (keys(%{$input->{commands}})) {
    	if (defined($gflist->{$gf})) {
    		$output->{$gf} = $gflist->{$gf};
    		if (lc($input->{commands}->{$gf}) eq "d") {
    			push(@{$rmlist},$input->{model_obj}->wsmeta()->[2]."gapfilling/".$gf);#Deleting job result object
    			push(@{$rmlist},$input->{model_obj}->wsmeta()->[2]."gapfilling/.".$gf);#Deleting job result directory
    		} elsif (lc($input->{commands}->{$gf}) eq "i") {
    			if (!defined($input->{selected_solutions}->{$gf})) {
    				$input->{selected_solutions}->{$gf} = 0;
    			}
    			$output->{$gf}->{integrated} = 1;
    			$output->{$gf}->{integrated_solution} = $input->{selected_solutions}->{$gf};
    			push(@{$updatelist},[$input->{model_obj}->wsmeta()->[2]."gapfilling/.".$gf."/".$gf.".fba",{
    				integrated => 1,
    				integrated_solution => $input->{selected_solutions}->{$gf}
    			});
    		} elsif (lc($input->{commands}->{$gf}) eq "u") {
    			$output->{$gf}->{integrated} = 0;
    			$output->{$gf}->{integrated_solution} = -1;
    			push(@{$updatelist},[$input->{model_obj}->wsmeta()->[2]."gapfilling/.".$gf."/".$gf.".fba",{
    				integrated => 0,
    				integrated_solution => -1
    			});
    		}
    	}
    }
    $self->helper()->workspace_service()->update_metadata({
		objects => $updatelist,
		adminmode => $self->helper()->adminmode()
    });
    $self->helper()->workspace_service()->delete({
		objects => $rmlist,
		deleteDirectories => 1,
		force => 1,
		adminmode => $self->helper()->adminmode()
    });
    #END manage_gapfill_solutions
    my @_bad_returns;
    (ref($output) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to manage_gapfill_solutions:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'manage_gapfill_solutions');
    }
    return($output);
}




=head2 list_fba_studies

  $output = $obj->list_fba_studies($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a list_fba_studies_params
$output is a reference to a hash where the key is a fba_id and the value is a fba_data
list_fba_studies_params is a reference to a hash where the following keys are defined:
	model has a value which is a ref
ref is a string
fba_id is a string
fba_data is a reference to a hash where the following keys are defined:
	rundate has a value which is a timestamp
	id has a value which is a fba_id
	fba has a value which is a ref
	objective has a value which is a float
	media has a value which is a ref
	objective_function has a value which is a string
timestamp is a string

</pre>

=end html

=begin text

$input is a list_fba_studies_params
$output is a reference to a hash where the key is a fba_id and the value is a fba_data
list_fba_studies_params is a reference to a hash where the following keys are defined:
	model has a value which is a ref
ref is a string
fba_id is a string
fba_data is a reference to a hash where the following keys are defined:
	rundate has a value which is a timestamp
	id has a value which is a fba_id
	fba has a value which is a ref
	objective has a value which is a float
	media has a value which is a ref
	objective_function has a value which is a string
timestamp is a string


=end text



=item Description



=back

=cut

sub list_fba_studies
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_fba_studies:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_fba_studies');
    }

    my $ctx = $Bio::ModelSEED::ProbModelSEED::Service::CallContext;
    my($output);
    #BEGIN list_fba_studies
    $input = $self->initialize_call($input);
    $output = $self->_list_fba_studies($input);
    #END list_fba_studies
    my @_bad_returns;
    (ref($output) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_fba_studies:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_fba_studies');
    }
    return($output);
}




=head2 delete_fba_studies

  $output = $obj->delete_fba_studies($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a delete_fba_studies_params
$output is a reference to a hash where the key is a fba_id and the value is a fba_data
delete_fba_studies_params is a reference to a hash where the following keys are defined:
	model has a value which is a ref
	commands has a value which is a reference to a hash where the key is a gapfill_id and the value is a gapfill_command
ref is a string
gapfill_id is a string
gapfill_command is a string
fba_id is a string
fba_data is a reference to a hash where the following keys are defined:
	rundate has a value which is a timestamp
	id has a value which is a fba_id
	fba has a value which is a ref
	objective has a value which is a float
	media has a value which is a ref
	objective_function has a value which is a string
timestamp is a string

</pre>

=end html

=begin text

$input is a delete_fba_studies_params
$output is a reference to a hash where the key is a fba_id and the value is a fba_data
delete_fba_studies_params is a reference to a hash where the following keys are defined:
	model has a value which is a ref
	commands has a value which is a reference to a hash where the key is a gapfill_id and the value is a gapfill_command
ref is a string
gapfill_id is a string
gapfill_command is a string
fba_id is a string
fba_data is a reference to a hash where the following keys are defined:
	rundate has a value which is a timestamp
	id has a value which is a fba_id
	fba has a value which is a ref
	objective has a value which is a float
	media has a value which is a ref
	objective_function has a value which is a string
timestamp is a string


=end text



=item Description



=back

=cut

sub delete_fba_studies
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to delete_fba_studies:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'delete_fba_studies');
    }

    my $ctx = $Bio::ModelSEED::ProbModelSEED::Service::CallContext;
    my($output);
    #BEGIN delete_fba_studies
    $input = $self->initialize_call($input);
    $input = $self->helper()->validate_args($input,["model","fbas"],{});
    my $fbalist = $self->_list_fba_studies($input);
    my $rmlist = [];
    for (my $i=0; $i < @{$input->{fbas}}; $i++) {
    	if (defined($fbalist->{$input->{fbas}->[$i]})) {
    		$output->{$input->{fbas}->[$i]} = $fbalist->{$input->{fbas}->[$i]};
    		push(@{$rmlist},$input->{model_obj}->wsmeta()->[2]."fba/".$input->{fbas}->[$i]);#Deleting job result object
    		push(@{$rmlist},$input->{model_obj}->wsmeta()->[2]."fba/.".$input->{fbas}->[$i]);#Deleting job result directory
    	}
    }
    $self->helper()->workspace_service()->delete({
		objects => $rmlist,
		deleteDirectories => 1,
		force => 1,
		adminmode => $self->helper()->adminmode()
    });
    #END delete_fba_studies
    my @_bad_returns;
    (ref($output) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to delete_fba_studies:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'delete_fba_studies');
    }
    return($output);
}




=head2 list_model_edits

  $output = $obj->list_model_edits($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a list_model_edits_params
$output is a reference to a hash where the key is an edit_id and the value is an edit_data
list_model_edits_params is a reference to a hash where the following keys are defined:
	model has a value which is a ref
ref is a string
edit_id is a string
edit_data is a reference to a hash where the following keys are defined:
	rundate has a value which is a timestamp
	id has a value which is an edit_id
	edit has a value which is a ref
	reactions_to_delete has a value which is a reference to a list where each element is a reaction_id
	altered_directions has a value which is a reference to a hash where the key is a reaction_id and the value is a reaction_direction
	altered_gpr has a value which is a reference to a hash where the key is a reaction_id and the value is a reference to a list where each element is a reference to a list where each element is a reference to a list where each element is a feature_id
	reactions_to_add has a value which is a reference to a list where each element is an edit_reaction
	altered_biomass_compound has a value which is a reference to a hash where the key is a compound_id and the value is a reference to a list containing 2 items:
	0: a float
	1: a compartment_id

timestamp is a string
reaction_id is a string
reaction_direction is a string
feature_id is a string
edit_reaction is a reference to a hash where the following keys are defined:
	id has a value which is a reaction_id
	reagents has a value which is a reference to a list where each element is a reference to a list containing 3 items:
	0: (compound) a string
	1: (coefficient) a float
	2: (compartment) a string

	gpr has a value which is a reference to a list where each element is a reference to a list where each element is a reference to a list where each element is a feature_id
	direction has a value which is a reaction_direction
compound_id is a string
compartment_id is a string

</pre>

=end html

=begin text

$input is a list_model_edits_params
$output is a reference to a hash where the key is an edit_id and the value is an edit_data
list_model_edits_params is a reference to a hash where the following keys are defined:
	model has a value which is a ref
ref is a string
edit_id is a string
edit_data is a reference to a hash where the following keys are defined:
	rundate has a value which is a timestamp
	id has a value which is an edit_id
	edit has a value which is a ref
	reactions_to_delete has a value which is a reference to a list where each element is a reaction_id
	altered_directions has a value which is a reference to a hash where the key is a reaction_id and the value is a reaction_direction
	altered_gpr has a value which is a reference to a hash where the key is a reaction_id and the value is a reference to a list where each element is a reference to a list where each element is a reference to a list where each element is a feature_id
	reactions_to_add has a value which is a reference to a list where each element is an edit_reaction
	altered_biomass_compound has a value which is a reference to a hash where the key is a compound_id and the value is a reference to a list containing 2 items:
	0: a float
	1: a compartment_id

timestamp is a string
reaction_id is a string
reaction_direction is a string
feature_id is a string
edit_reaction is a reference to a hash where the following keys are defined:
	id has a value which is a reaction_id
	reagents has a value which is a reference to a list where each element is a reference to a list containing 3 items:
	0: (compound) a string
	1: (coefficient) a float
	2: (compartment) a string

	gpr has a value which is a reference to a list where each element is a reference to a list where each element is a reference to a list where each element is a feature_id
	direction has a value which is a reaction_direction
compound_id is a string
compartment_id is a string


=end text



=item Description



=back

=cut

sub list_model_edits
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_model_edits:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_model_edits');
    }

    my $ctx = $Bio::ModelSEED::ProbModelSEED::Service::CallContext;
    my($output);
    #BEGIN list_model_edits
    $input = $self->initialize_call($input);
    $output = $self->_list_model_edits($input);
    #END list_model_edits
    my @_bad_returns;
    (ref($output) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_model_edits:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_model_edits');
    }
    return($output);
}




=head2 manage_model_edits

  $output = $obj->manage_model_edits($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a manage_model_edits_params
$output is a reference to a hash where the key is an edit_id and the value is an edit_data
manage_model_edits_params is a reference to a hash where the following keys are defined:
	model has a value which is a ref
	commands has a value which is a reference to a hash where the key is an edit_id and the value is a gapfill_command
	new_edit has a value which is an edit_data
ref is a string
edit_id is a string
gapfill_command is a string
edit_data is a reference to a hash where the following keys are defined:
	rundate has a value which is a timestamp
	id has a value which is an edit_id
	edit has a value which is a ref
	reactions_to_delete has a value which is a reference to a list where each element is a reaction_id
	altered_directions has a value which is a reference to a hash where the key is a reaction_id and the value is a reaction_direction
	altered_gpr has a value which is a reference to a hash where the key is a reaction_id and the value is a reference to a list where each element is a reference to a list where each element is a reference to a list where each element is a feature_id
	reactions_to_add has a value which is a reference to a list where each element is an edit_reaction
	altered_biomass_compound has a value which is a reference to a hash where the key is a compound_id and the value is a reference to a list containing 2 items:
	0: a float
	1: a compartment_id

timestamp is a string
reaction_id is a string
reaction_direction is a string
feature_id is a string
edit_reaction is a reference to a hash where the following keys are defined:
	id has a value which is a reaction_id
	reagents has a value which is a reference to a list where each element is a reference to a list containing 3 items:
	0: (compound) a string
	1: (coefficient) a float
	2: (compartment) a string

	gpr has a value which is a reference to a list where each element is a reference to a list where each element is a reference to a list where each element is a feature_id
	direction has a value which is a reaction_direction
compound_id is a string
compartment_id is a string

</pre>

=end html

=begin text

$input is a manage_model_edits_params
$output is a reference to a hash where the key is an edit_id and the value is an edit_data
manage_model_edits_params is a reference to a hash where the following keys are defined:
	model has a value which is a ref
	commands has a value which is a reference to a hash where the key is an edit_id and the value is a gapfill_command
	new_edit has a value which is an edit_data
ref is a string
edit_id is a string
gapfill_command is a string
edit_data is a reference to a hash where the following keys are defined:
	rundate has a value which is a timestamp
	id has a value which is an edit_id
	edit has a value which is a ref
	reactions_to_delete has a value which is a reference to a list where each element is a reaction_id
	altered_directions has a value which is a reference to a hash where the key is a reaction_id and the value is a reaction_direction
	altered_gpr has a value which is a reference to a hash where the key is a reaction_id and the value is a reference to a list where each element is a reference to a list where each element is a reference to a list where each element is a feature_id
	reactions_to_add has a value which is a reference to a list where each element is an edit_reaction
	altered_biomass_compound has a value which is a reference to a hash where the key is a compound_id and the value is a reference to a list containing 2 items:
	0: a float
	1: a compartment_id

timestamp is a string
reaction_id is a string
reaction_direction is a string
feature_id is a string
edit_reaction is a reference to a hash where the following keys are defined:
	id has a value which is a reaction_id
	reagents has a value which is a reference to a list where each element is a reference to a list containing 3 items:
	0: (compound) a string
	1: (coefficient) a float
	2: (compartment) a string

	gpr has a value which is a reference to a list where each element is a reference to a list where each element is a reference to a list where each element is a feature_id
	direction has a value which is a reaction_direction
compound_id is a string
compartment_id is a string


=end text



=item Description



=back

=cut

sub manage_model_edits
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to manage_model_edits:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'manage_model_edits');
    }

    my $ctx = $Bio::ModelSEED::ProbModelSEED::Service::CallContext;
    my($output);
    #BEGIN manage_model_edits
    $input = $self->initialize_call($input);
    $input = $self->helper()->validate_args($input,["model","commands"],{
    	new_edit => {}
    });
    my $list = $self->_list_model_edits($input);
    my $rmlist = [];
    my $updatelist = [];
    foreach my $edit (keys(%{$input->{commands}})) {
    	if (defined($list->{$edit})) {
    		$output->{$edit} = $list->{$edit};
    		if (lc($input->{commands}->{$edit}) eq "d") {
    			push(@{$rmlist},$input->{model_obj}->wsmeta()->[2]."edits/".$edit.".model_edit");
    		} elsif (lc($input->{commands}->{$edit}) eq "i") {
    			$output->{$edit}->{integrated} = 1;
    			push(@{$updatelist},[$input->{model_obj}->wsmeta()->[2]."edits/".$edit.".model_edit",{
    				integrated => 1,
    			});
    		} elsif (lc($input->{commands}->{$edit}) eq "u") {
    			$output->{$edit}->{integrated} = 0;
    			push(@{$updatelist},[$input->{model_obj}->wsmeta()->[2]."edits/".$edit.".model_edit",{
    				integrated => 0,
    			});
    		}
    	}
    }
    $self->helper()->workspace_service()->update_metadata({
		objects => $updatelist,
		adminmode => $self->helper()->adminmode()
    });
    $self->helper()->workspace_service()->delete({
		objects => $rmlist,
		deleteDirectories => 1,
		force => 1,
		adminmode => $self->helper()->adminmode()
    });
    if (defined($input->{new_edit})) {
    	my $editmeta = {
    		integrated => 1,
    	};
    	my $editobj = $self->helper()->validate_args($input->{new_edit},["id"],{
	    	reactions_to_delete => [],
	    	altered_directions => {},
	    	altered_gpr => {},
	    	reactions_to_add => [],
	    	altered_biomass_compound => {}
	    });
	    $editmeta->{editdata} = Bio::KBase::ObjectAPI::utilities::TOJSON($editobj);
    	$self->helper()->workspace_service()->create({
    		objects => [[
    			$input->{model_obj}->wsmeta()->[2]."edits/".$input->{new_edit}->{id}.".model_edit",
    			"model_edit",
    			$editmeta,
    			$editobj
    		]],
    		overwrite => 1,
    		adminmode => $self->helper()->adminmode()
    	});
    	$output->{$editobj->{id}} = $editobj;
    };
    #END manage_model_edits
    my @_bad_returns;
    (ref($output) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to manage_model_edits:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'manage_model_edits');
    }
    return($output);
}




=head2 version 

  $return = $obj->version()

=over 4

=item Parameter and return types

=begin html

<pre>
$return is a string
</pre>

=end html

=begin text

$return is a string

=end text

=item Description

Return the module version. This is a Semantic Versioning number.

=back

=cut

sub version {
    return $VERSION;
}

=head1 TYPES



=head2 bool

=over 4



=item Description

********************************************************************************
    Universal simple type definitions
   	********************************************************************************


=item Definition

=begin html

<pre>
an int
</pre>

=end html

=begin text

an int

=end text

=back



=head2 ref

=over 4



=item Description

Reference to location in PATRIC workspace (e.g. /home/chenry/models/MyModel)


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 timestamp

=over 4



=item Description

Standard perl timestamp (e.g. 2015-03-21-02:14:53)


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 gapfill_id

=over 4



=item Description

ID of gapfilling solution


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 fba_id

=over 4



=item Description

ID of FBA study


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 edit_id

=over 4



=item Description

ID of model edits


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 gapfill_command

=over 4



=item Description

An enum of commands to manage gapfilling solutions [D/I/U]; D = delete, I = integrate, U = unintegrate


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 reaction_id

=over 4



=item Description

ID of reaction in model


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 compound_id

=over 4



=item Description

ID of compound in model


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 feature_id

=over 4



=item Description

ID of feature in model


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 compartment_id

=over 4



=item Description

ID of compartment in model


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 reaction_direction

=over 4



=item Description

An enum of directions for reactions [</=/>]; < = reverse, = = reversible, > = forward


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 gapfill_reaction

=over 4



=item Description

********************************************************************************
    Complex data structures to support functions
   	********************************************************************************


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
reaction has a value which is a ref
direction has a value which is a reaction_direction
compartment has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
reaction has a value which is a ref
direction has a value which is a reaction_direction
compartment has a value which is a string


=end text

=back



=head2 gapfill_data

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
rundate has a value which is a timestamp
id has a value which is a gapfill_id
gapfill has a value which is a ref
media has a value which is a ref
integrated has a value which is a bool
integrated_solution has a value which is an int
solution_reactions has a value which is a reference to a list where each element is a reference to a list where each element is a gapfill_reaction

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
rundate has a value which is a timestamp
id has a value which is a gapfill_id
gapfill has a value which is a ref
media has a value which is a ref
integrated has a value which is a bool
integrated_solution has a value which is an int
solution_reactions has a value which is a reference to a list where each element is a reference to a list where each element is a gapfill_reaction


=end text

=back



=head2 fba_data

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
rundate has a value which is a timestamp
id has a value which is a fba_id
fba has a value which is a ref
objective has a value which is a float
media has a value which is a ref
objective_function has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
rundate has a value which is a timestamp
id has a value which is a fba_id
fba has a value which is a ref
objective has a value which is a float
media has a value which is a ref
objective_function has a value which is a string


=end text

=back



=head2 edit_reaction

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is a reaction_id
reagents has a value which is a reference to a list where each element is a reference to a list containing 3 items:
0: (compound) a string
1: (coefficient) a float
2: (compartment) a string

gpr has a value which is a reference to a list where each element is a reference to a list where each element is a reference to a list where each element is a feature_id
direction has a value which is a reaction_direction

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is a reaction_id
reagents has a value which is a reference to a list where each element is a reference to a list containing 3 items:
0: (compound) a string
1: (coefficient) a float
2: (compartment) a string

gpr has a value which is a reference to a list where each element is a reference to a list where each element is a reference to a list where each element is a feature_id
direction has a value which is a reaction_direction


=end text

=back



=head2 edit_data

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
rundate has a value which is a timestamp
id has a value which is an edit_id
edit has a value which is a ref
reactions_to_delete has a value which is a reference to a list where each element is a reaction_id
altered_directions has a value which is a reference to a hash where the key is a reaction_id and the value is a reaction_direction
altered_gpr has a value which is a reference to a hash where the key is a reaction_id and the value is a reference to a list where each element is a reference to a list where each element is a reference to a list where each element is a feature_id
reactions_to_add has a value which is a reference to a list where each element is an edit_reaction
altered_biomass_compound has a value which is a reference to a hash where the key is a compound_id and the value is a reference to a list containing 2 items:
0: a float
1: a compartment_id


</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
rundate has a value which is a timestamp
id has a value which is an edit_id
edit has a value which is a ref
reactions_to_delete has a value which is a reference to a list where each element is a reaction_id
altered_directions has a value which is a reference to a hash where the key is a reaction_id and the value is a reaction_direction
altered_gpr has a value which is a reference to a hash where the key is a reaction_id and the value is a reference to a list where each element is a reference to a list where each element is a reference to a list where each element is a feature_id
reactions_to_add has a value which is a reference to a list where each element is an edit_reaction
altered_biomass_compound has a value which is a reference to a hash where the key is a compound_id and the value is a reference to a list containing 2 items:
0: a float
1: a compartment_id



=end text

=back



=head2 list_gapfill_solutions_params

=over 4



=item Description

********************************************************************************
    Functions for managing gapfilling studies
   	********************************************************************************


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
model has a value which is a ref

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
model has a value which is a ref


=end text

=back



=head2 manage_gapfill_solutions_params

=over 4



=item Description

FUNCTION: manage_gapfill_solutions
DESCRIPTION: This function manages the gapfill solutions for a model and returns gapfill solution data

REQUIRED INPUTS:
ref model - reference to model to integrate solutions for
mapping<gapfill_id,gapfill_command> commands - commands to manage gapfill solutions

OPTIONAL INPUTS:
mapping<gapfill_id,int> selected_solutions - solutions to integrate


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
model has a value which is a ref
commands has a value which is a reference to a hash where the key is a gapfill_id and the value is a gapfill_command
selected_solutions has a value which is a reference to a hash where the key is a gapfill_id and the value is an int

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
model has a value which is a ref
commands has a value which is a reference to a hash where the key is a gapfill_id and the value is a gapfill_command
selected_solutions has a value which is a reference to a hash where the key is a gapfill_id and the value is an int


=end text

=back



=head2 list_fba_studies_params

=over 4



=item Description

********************************************************************************
    Functions for managing FBA studies
   	********************************************************************************


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
model has a value which is a ref

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
model has a value which is a ref


=end text

=back



=head2 delete_fba_studies_params

=over 4



=item Description

FUNCTION: delete_fba_studies
DESCRIPTION: This function deletes fba studies associated with model

REQUIRED INPUTS:
ref model - reference to model to integrate solutions for
list<fba_id> fbas - list of FBA studies to delete


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
model has a value which is a ref
commands has a value which is a reference to a hash where the key is a gapfill_id and the value is a gapfill_command

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
model has a value which is a ref
commands has a value which is a reference to a hash where the key is a gapfill_id and the value is a gapfill_command


=end text

=back



=head2 list_model_edits_params

=over 4



=item Description

********************************************************************************
    Functions for editing models
   	********************************************************************************


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
model has a value which is a ref

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
model has a value which is a ref


=end text

=back



=head2 manage_model_edits_params

=over 4



=item Description

FUNCTION: manage_model_edits
DESCRIPTION: This function manages edits to model submitted by user

REQUIRED INPUTS:
ref model - reference to model to integrate solutions for
mapping<edit_id,gapfill_command> commands - list of edit commands

OPTIONAL INPUTS:
edit_data new_edit - list of new edits to add


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
model has a value which is a ref
commands has a value which is a reference to a hash where the key is an edit_id and the value is a gapfill_command
new_edit has a value which is an edit_data

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
model has a value which is a ref
commands has a value which is a reference to a hash where the key is an edit_id and the value is a gapfill_command
new_edit has a value which is an edit_data


=end text

=back



=cut

1;
