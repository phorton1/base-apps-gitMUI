#----------------------------------------------------
# base::apps::gitUI::repo
#----------------------------------------------------



package apps::gitUI::repo;
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Utils;
use apps::gitUI::git;


my $dbg_new = 1;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(

	);
}



sub new
{
	my ($class, $num, $section, $path, $branch) = @_;
	my $this = shared_clone({
		num 	=> $num,
		path 	=> $path,
		id      => repoPathToId($path),
		section => $section,
		branch	=> $branch || 'master',

		private  => 0,						# if PRIVATE in file
		selected => 0,						# if selected for commit, tag, push
		parent   => '',						# "Forked from ..." or "Copied from ..."
		descrip  => '',						# description from github
		uses 	 => shared_clone([]),		# a list of the repositories this repository USES
		needs	 => shared_clone([]),       # a list of the abitrary dependencies this repository has
		friend   => shared_clone([]),       # a hash of repositories this repository relates to or can use
		group    => shared_clone([]),       # a list of arbitrary groups that this repository belongs to
		local_changes => '',				# list of lines of change text matching 'local: ...'
		remote_changes => '',				# list of lines of change text matching 'remote: ...'
		errors   => shared_clone([]),
		warnings => shared_clone([]),
		notes 	 => shared_clone([]), });
	display($dbg_new,0,"repo->new($num,$section,$path,$branch)");
	bless $this,$class;
	return $this;
}


#----------------------------
# accessors
#----------------------------

sub clearErrors
{
	my ($this) = @_;
	$this->{errors}   = shared_clone([]);
	$this->{warnings} = shared_clone([]);
	$this->{notes} = shared_clone([]);
}


sub addChange
{
	my ($this,$where,$what) = @_;
	$what =~ s/^\s+|\s+$//g;
	my $key = $where."_changes";
	$this->{$key} ||= shared_clone([]);
	push @{$this->{$key}},$what;
}


sub setChanges
{
	my ($this,$text) = @_;
	my @lines = split(/\n/,$text);
	for my $line (@lines)
	{
		$this->addChange($1,$line) if
			$line =~ s/^\s*(remote|local):\s*//;
	}
}




1;
