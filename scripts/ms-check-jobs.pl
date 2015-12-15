use strict;
use Bio::P3::Workspace::ScriptHelpers;
use Bio::KBase::AppService::Client;

my($opt, $usage) = Bio::P3::Workspace::ScriptHelpers::options("%c %o",[
	["jobid|j","Job ID to view full details for"]
]);
my $client = Bio::P3::Workspace::ScriptHelpers::msClient();
if (defined($opt->{jobid})) {
	my $jobstatus = $client->CheckJobs({jobs => [$opt->{jobid}]});
	print Data::Dumper->Dump($jobstatus->{$opt->{jobid}})."\n";
} else {
	my $jobstatus = $client->CheckJobs({});
	my $tbl = [];   
	foreach my $task (keys(%{$jobstatus})) {
		my $job = $jobstatus->{$task};
		push(@$tbl, [$job->{id},$job->{app},$job->{status},$job->{submit_time},$job->{start_time},$job->{completed_time},$job->{stdout_shock_node},$job->{stderr_shock_node}]);
	}
	my $table = Text::Table->new(
		"Task","App","Status","Submitted","Started","Completed","Stdout","Stderr"
	);
	$table->load(@{$tbl});
	print $table."\n";
}