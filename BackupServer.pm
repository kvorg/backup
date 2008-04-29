# -*- perl -*-

package BackupServer;

use Backup;
use strict;

##################################################
### read the config file

sub get_config_file {
  my $configuration = shift;

  my $file = Backup::canonical_filename($configuration->{SERVER_CONF_FILE},
					$configuration->{SERVER_BASEDIR});

  open (F, "$file") or log_fatal "Could not open $file.";

  my @data;
  chomp (@data = <F>);

  close F or log_fatal "Could not close $file.";

  log_verbose "Configuration file:\n" . ("-" x 70) . "\n";
  log_verbose join("\n", @data);
  log_verbose "\n" . ("-" x 70) . "\n\n";

  Backup::parse_config(\@data, $configuration, $file);
}

##################################################
### main server routine

sub handle {
  my $configuration = shift;

  ### read the config file
 
  get_config_file($configuration);

  log_verbose ("Configuration:\n" . ("-" x 70) . "\n" .
	       config_to_string($configuration) . "\n" .
	      ("-" x 70) . "\n");

  my $basedir = $configuration->{SERVER_BASEDIR};
 
  if ($configuration->{BACKUP}) {
    ### get the date in suitable format
  
    my $date = `date '+%Y_%m_%d_%H_%M_%S'` or log_fatal "Could not obtain the date.";
    chomp $date;

    ### find the latest backup, if there is one,
    ### and make a fresh copy of it

    my @backups = `ls -dt $basedir/backup_* 2>/dev/null`;
    
    if ($#backups >= 0) {
      chomp(@backups);
      @backups = sort(@backups);

      log_verbose "The following backups were found:\n" .
	join("\n", @backups) . "\n\n";

      my $latest = $backups[-1];

      log_verbose "Latest backup is $latest\n\n";

      ### copy (or create) the directory in which we put the backup
      
      run "cp -al $latest $basedir/inprogress_$date";
    }
    else {
      log_verbose "No backups were found. Creating an initial one.\n";

      run "mkdir -p $basedir/inprogress_$date";
    }

    ### compute the rsync parameters

    my $sshid = Backup::canonical_filename($configuration->{SERVER_SSH_ID}, $basedir);
    my $from = $configuration->{CLIENT} . ":" . $configuration->{CLIENT_BASEDIR};
    my $to = "$basedir/inprogress_$date";
    my $excludes = "";
    my $useropts = $configuration->{OPTIONS_RSYNC};


    foreach my $e (@{$configuration->{EXCLUDE}}) {
      if ($e =~ m|^\-(.*)|) {
	$excludes .= " --exclude \'$1\'";
      }
      elsif ($e =~ m|^\+(.*)|) {
	$excludes .= " --include \'$1\'";
      }
    }
      
    ### run rsync on the directory

    run "rsync -azHS --delete $useropts $excludes -e \"ssh -i $sshid\" $from $to";

    ### rename the backup directory

    run "mv $basedir/inprogress_$date $basedir/backup_$date";

    ### fix the "latest" soft link

    run "if [ -h $basedir/latest ]; then rm $basedir/latest; fi";

    run "ln -s backup_$date $basedir/latest";
  }

  ### now delete old backups if necessary

  if ($configuration->{DELETE}) {
    ### recompute the list of backups since we just made a new one
    
    my @backups = `ls -d1t $basedir/backup_* 2>/dev/null`;

    if ($#backups < 0) {
      log_verbose "No backups were found, nothing to delete.\n";
    }
    else {
      chomp(@backups);

      foreach my $b (@backups) {
	$b =~ s/^.*backup_(\d+)_(\d+)_(\d+)_(\d+)_(\d+)_(\d+)$/\1-\2-\3 \4:\5:\6/;
      }

      sort(@backups);

      ### get the list of the backups that need to be KEPT

      my $kept = Backup::kept_backups(\@backups, $configuration);

      my %lookup;

      foreach my $f (@$kept) {
	$f=~ s|(\d+)-(\d+)-(\d+)\ (\d+):(\d+):(\d+)|$basedir/backup_\1_\2_\3_\4_\5_\6|;
	$lookup{$f} = 1;
      }

      log_verbose "The following backups must be kept:\n" .
	join("\n", (sort (keys %lookup))) . "\n\n";
      
      ### remove 1 non-kept backup

      my @backups = `ls -dt $basedir/backup_*`
	or log_fatal "Should have found some backups. Where are they?";
      chomp(@backups);
    
      foreach my $b (@backups) {
	if ($lookup{$b} != 1) {
	  log_message "Removing the backup $b\n";
	  my $f = $b;
	  $f =~ s|backup_(\d+_\d+_\d+_\d+_\d+_\d+)$|deleting_\1|;
	  run "mv $b $f";
	  run "rm -rf $f";
	  last;
	}
      }
    }
  }

  log_success "";

}

##################################################
# make perl happy

1;

##################################################
# the end
