#---------------------------------------------
# PreInstallApp.pm
#---------------------------------------------
# Script run directly from Cava Packager after building
# but before creating the installer.  This program reads
# and modifies the innosetup.iss file in the Cava project's
# installer dir.
#
# Gleaned and Modified from examples in Program File (x86)/Innosetup
#
# There are several things this script does.
#
# First it is required to remove or add lines innosetup.iss
# to make it compatible with Innosetup version 5.5.9 so that
# it works at all.
#
#     MinVersion=whatever removed as it was causing problems.
#     OutputManifestFile apparently no longer accepts a path
#		  and so is removed
#     The Basque and Slovak languages are no longer available
#         Innosetup includes a huge list of install languages
#         including some that don't work and cause the build
#         to fail. Having a language choice available in the
#         is a vanity, which I DID use for CM (en and es),
#         but generally, I just remove the entire [Language]
#         section from innosetup.iss.  See CM's installer for
#         an example of how to add specific languages, and
#         a window to choose the installer language, back into
#         the installer.
#
# Secondly it adds or remove lines that I generally prefer
# in my installers. For example:
#
#     CloseApplications=force added to force the user to
#         exit the application if it is running.
#
# And Finally, it can application specific stuff to the
# script by specifying a [Code] section that includes
# variables and/or callbacks to includes other (pascal)
# .iss files into the script.
#
#------------------------------------------------------------------------
#
# To run innosetup compiler from dos box
#   C:\Program Files (x86)\Cava Packager 2.0\innosetup\iscc /Qp C:\base_dist\cmManagerRelease\installer\innosetup.iss
#   /Qp = Quiet except for errors and warnings
#   /O- adds "syntax check only" but does delete the contents of the existing build
#   /O"/junk/test_installer" wipes out a different directory instead
# Komodo "Run" RE's Warning: (?P<file>.+?), Line (?P<line>\d+), Column (?P<content>.*))$


use strict;
use warnings;

my $ADD_ENV_PATH = 1;
	# includes code to add the /bin path to the PATH (Registry)
	# on install and removes it on uninstall.

my $USE_INNOSETUP_559 = 1;
    # Set to 1 to filter out and change lines that
    # Cava produces that are incompatible with
    # innotsetup 5.5.9 (and later) version(s).

my $USE_CAVA_POST_PL = 0;
    # Set to 0 to filter out Cava do-install calls.
	# I generally don't use this feature of Cava's
	# interface to Innosetup.

my $text = '';
my $installerdir = $ARGV[1];
my $unused_releaseddir = $ARGV[0];
my $iss_file = "$installerdir/innosetup.iss";

utf8::upgrade($text);


#---------------------------------------------------
# processLine
#---------------------------------------------------
# the [Languages] section is at the end of the file
# and entirely removed.

my $in_language = 0;


sub commentLine
{
    my ($line) = @_;
    return "; following line commented out by PreInstallApp.pm\n; $line";
}


sub processLine
    # Do innotsetup 5.5.9u specific fixups
{
    my ($line) = @_;

	if ($line && $in_language)
	{
		$line = "; $line";
	}
	elsif ($line eq '[Languages]')
	{
		$in_language = 1;
		$line = "; existing Languages section commented out by PreInstallerApp.pm\n; $line"
	}
    elsif ($line eq '[Setup]')
    {
		# These are my standard installer preferences

        $line .= "\n".
			"; following Setup lines added by PreInstallerApp.pm\n".
			"DisableDirPage=yes\n".
            "ShowLanguageDialog=no\n".
            "DisableProgramGroupPage=yes\n".
            "RestartIfNeededByRun=no";

		# These are required for Innosetup 5.5.9 and later

        $line .= "\n" .
            "CloseApplications=force\n".
            "OutputManifestFile=innosetup.manifest"
            if $USE_INNOSETUP_559;

		$line .= "\n".
			"ChangesEnvironment=true"
			if $ADD_ENV_PATH;

        $line .= "\n; end of added Setup lines\n";
    }

	# These are preferences, although MinVersion may be requred

    elsif ($line =~ /^DisableDirPage=/ ||
           $line =~ /ShowLanguageDialog=/ ||
           $line =~ /^DisableProgramGroupPage=/ ||
           $line =~ /^RestartIfNeededByRun=/ ||
           $line =~ /^CloseApplications=/ ||
           $line =~ /^OutputManifestFile=/ ||
           $line =~ /^MinVersion=/ ||
           $line =~ /Basque|Slovak/)
    {
        $line = commentLine($line);  # undef;
    }

	# I generally don't use the Cava post installer stuff

    elsif ($line =~ /\\bin\\do-install\.exe/ &&
           !$USE_CAVA_POST_PL)
    {
        $line = commentLine($line);  # undef;
    }

    return $line;
}


#---------------------------------------------------
# $ADD_ENV_PATH stuff
#----------------------------------------------------
# Copied from https://stackoverflow.com/questions/3304463/how-do-i-modify-the-path-environment-variable-when-running-an-inno-setup-install
# Note: Upon install the path is available immediately, but on uinstall the path is removed from the registry, but remains in
# effect unti the next reboot.

sub addEnvPathCode
{
	return <<EO_ADD_ENV_PATH;
[Code]

const EnvironmentKey = 'SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment';

procedure EnvAddPath(Path: string);
var
	Paths: string;
begin
	{ Retrieve current path (use empty string if entry not exists) }
	if not RegQueryStringValue(HKEY_LOCAL_MACHINE, EnvironmentKey, 'Path', Paths)
	then Paths := '';

	{ Skip if string already found in path }
	if Pos(';' + Uppercase(Path) + ';', ';' + Uppercase(Paths) + ';') > 0 then exit;

	{ App string to the end of the path variable }
	Paths := Paths + ';'+ Path +';'

	{ Overwrite (or create if missing) path environment variable }
	if RegWriteStringValue(HKEY_LOCAL_MACHINE, EnvironmentKey, 'Path', Paths)
	then Log(Format('The [%s] added to PATH: [%s]', [Path, Paths]))
	else Log(Format('Error while adding the [%s] to PATH: [%s]', [Path, Paths]));
end;


procedure EnvRemovePath(Path: string);
var
	Paths: string;
	P: Integer;
begin
	{ Skip if registry entry not exists }
	if not RegQueryStringValue(HKEY_LOCAL_MACHINE, EnvironmentKey, 'Path', Paths) then
		exit;

	{ Skip if string not found in path }
	P := Pos(';' + Uppercase(Path) + ';', ';' + Uppercase(Paths) + ';');
	if P = 0 then exit;

	{ Update path variable }
	Delete(Paths, P - 1, Length(Path) + 1);

	{ Overwrite path environment variable }
	if RegWriteStringValue(HKEY_LOCAL_MACHINE, EnvironmentKey, 'Path', Paths)
	then Log(Format('The [%s] removed from PATH: [%s]', [Path, Paths]))
	else Log(Format('Error while removing the [%s] from PATH: [%s]', [Path, Paths]));
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
	if CurStep = ssPostInstall
	 then EnvAddPath(ExpandConstant('{app}') +'\\bin');
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
	if CurUninstallStep = usPostUninstall
	then EnvRemovePath(ExpandConstant('{app}') +'\\bin');
end;

EO_ADD_ENV_PATH
}



#---------------------------------------------------
# addNewStuff
#---------------------------------------------------
# The contents of this method are optional,
# depending on the application, and can be used
# to re-add a [Languages] section and/or add a
# new [Code] section

sub addNewStuff
{
	my $text = '';
	$text .= addEnvPathCode()
		if $ADD_ENV_PATH;
	return $text;
}



#---------------------------------------------------
# MAIN
#---------------------------------------------------
# Read the existing innosetup file and modify it.
# We process lines up EOF and comment out everything
# else in the file starting at any existing [Code] section.

open my $fh, "<$iss_file";
while(<$fh>)
{
    chomp;
    my $line = $_;

	if (defined($line))
	{
		$line = processLine($line);
		$text .= "$line\n";
	}
}
close($fh);


# add new [Code] section, if any

$text .= addNewStuff();

# write the new innnosetup.iss file

open $fh, ">$iss_file";
print $fh $text;
close($fh);

1;
