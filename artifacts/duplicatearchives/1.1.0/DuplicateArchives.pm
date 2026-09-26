package LANraragi::Plugin::Managed::Scripts::DuplicateArchives;

use strict;
use warnings;
use utf8;

use Redis;

use LANraragi::Model::Config;
use LANraragi::Utils::Generic qw(is_archive is_image);
use LANraragi::Utils::Logging qw(get_plugin_logger);
use LANraragi::Utils::Redis   qw(redis_decode);

# Meta-information about your plugin.
sub plugin_info {

    return (
        name        => "Duplicate Archive Finder",
        type        => "script",
        namespace   => "duplicatearchives",
        author      => "LemonSoda-RPG",
        version     => "1.1.0",
        description => "Lists archives that share the same LANraragi computed ID using the Shinobu filemap."
    );
}

# Mandatory function to be implemented by your script
sub run_script {
    shift;

    my $logger = get_plugin_logger();
    $logger->info("Duplicate Archive Finder started.");

    my $redis  = LANraragi::Model::Config->get_redis_config;

    my %filemap = $redis->exists("LRR_FILEMAP") ? $redis->hgetall("LRR_FILEMAP") : ();
    $redis->quit;

    my %archives_by_id;
    my ( $image_count, $nonarchive_count ) = ( 0, 0 );

    while ( my ( $raw_file, $archive_id ) = each %filemap ) {
        my $file = redis_decode($raw_file);

        if ( is_image($file) ) {
            $image_count++;
            next;
        }

        if ( !is_archive($file) ) {
            $nonarchive_count++;
            next;
        }

        push @{ $archives_by_id{$archive_id} }, $file;
    }

    my @duplicate_groups =
      map {
        {
            archive_id => $_,
            count      => scalar @{ $archives_by_id{$_} },
            files      => [ sort @{ $archives_by_id{$_} } ]
        }
      }
      sort {
             scalar @{ $archives_by_id{$b} } <=> scalar @{ $archives_by_id{$a} }
          || $archives_by_id{$a}[0] cmp $archives_by_id{$b}[0]
      }
      grep { @{ $archives_by_id{$_} } > 1 } keys %archives_by_id;

    my %result = (
        filemap_entries     => scalar( keys %filemap ),
        images_skipped      => $image_count,
        nonarchives_skipped => $nonarchive_count,
        duplicate_groups    => \@duplicate_groups,
        message             => "Duplicate Archive Finder finished. Found "
          . scalar(@duplicate_groups)
          . " duplicate archive groups. See Plugin Logs for details.",
        total               => scalar @duplicate_groups
    );

    log_duplicate_groups( $logger, \%result );
    $logger->info($result{message});

    return %result;
}

sub log_duplicate_groups {
    my ( $logger, $result ) = @_;

    $logger->info(
            "Filemap entries: $result->{filemap_entries}; "
          . "images skipped: $result->{images_skipped}; "
          . "non-archives skipped: $result->{nonarchives_skipped}; "
          . "duplicate groups: $result->{total}."
    );

    if ( !$result->{total} ) {
        $logger->info("No duplicate archives found.");
        return;
    }

    my $group_number = 0;
    for my $group ( @{ $result->{duplicate_groups} } ) {
        $group_number++;
        $logger->info(
            "Group $group_number: ID $group->{archive_id}; count $group->{count}."
        );
        $logger->info("  $_") for @{ $group->{files} };
    }
}

1;
