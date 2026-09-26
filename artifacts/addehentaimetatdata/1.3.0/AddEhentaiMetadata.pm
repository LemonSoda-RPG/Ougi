package LANraragi::Plugin::Managed::Scripts::AddEhentaiMetadata;

use strict;
use warnings;
use utf8;

use LANraragi::Model::Archive;
use LANraragi::Utils::Database qw(set_tags);
use LANraragi::Utils::Logging qw(get_plugin_logger);
use LANraragi::Utils::Plugins qw(use_plugin);
use LANraragi::Utils::Redis qw(redis_decode);

my $METADATA_PLUGIN = "etagcn";
my $NO_GALLERY_TAG  = "source:nogalleryinehentai";

# Meta-information about this script plugin.
sub plugin_info {

    return (
        name        => "Add ETagCN Metatdata",
        type        => "script",
        namespace   => "addehentaimetatdata",
        author      => "CHUSHEN",
        version     => "1.3.0",
        description => "Using the ETagCN plugin to search for metadata for files that do not have a source tag. If No matching EH Gallery Found!, will add source:nogalleryinehentai",
        oneshot_arg => "Search archives tagged source:nogalleryinehentai again. True/False",
        # 旧版本用数组式（按位置）保存参数，这里声明位置顺序以便自动迁移已保存的配置
        to_named_params => ['interval'],
        parameters  => {
            'interval' => { type => "int", desc => "Interval in seconds between requests. E-Hentai recommends at least 4 seconds." }
        }
    );
}

sub log_text {

    my ($value) = @_;
    return "" unless defined $value;
    return redis_decode($value);
}

# ETagCN returns this message when its search cannot find a gallery.
sub is_no_gallery_error {

    my ($error) = @_;

    return 0 unless defined $error;
    return $error =~ /No matching EH Gallery Found!|没有匹配的\s*E-Hentai\s*画廊/;
}

sub run_metadata_plugin {

    my ($arcid) = @_;

    my ( $plugin_info, $plugin_result );
    eval {
        ( $plugin_info, $plugin_result ) = use_plugin( $METADATA_PLUGIN, $arcid, undef );
    };

    if ($@) {
        $plugin_result = { error => $@ };
    }

    return $plugin_result || { error => "The E-Hentai_CN plugin returned no result." };
}

# Mandatory function to be implemented by a script plugin.
sub run_script {
    shift;

    my $lrr_info        = shift || {};
    my $params          = shift || {};
    my $logger          = get_plugin_logger();
    my $retry_unmatched = $lrr_info->{oneshot_param};
    my $interval        = $params->{interval};
    my $success         = 0;
    my $total           = 0;
    my @archives        = LANraragi::Model::Archive->generate_archive_list;

    $interval = 4 if !defined $interval || $interval < 0;

    for my $archive (@archives) {
        next if $archive->{tags} =~ /\bsource\b/;

        sleep($interval);
        $logger->info("Start ETagCN process: " . log_text( $archive->{title} ));
        $total++;

        my $plugin_result = run_metadata_plugin( $archive->{arcid} );
        if ( exists $plugin_result->{error} ) {
            $plugin_result->{error} = log_text( $plugin_result->{error} );
            $logger->warn("ETagCN plugin returned an error: " . $plugin_result->{error});

            if ( is_no_gallery_error( $plugin_result->{error} ) ) {
                $plugin_result->{new_tags} = $NO_GALLERY_TAG;
                $logger->info("Add tag: $NO_GALLERY_TAG");
            } else {
                next;
            }
        }

        if ( exists $plugin_result->{new_tags} ) {
            $plugin_result->{new_tags} = log_text( $plugin_result->{new_tags} );
            $logger->debug("Add ETagCN tags: " . $plugin_result->{new_tags});
            set_tags( $archive->{arcid}, $plugin_result->{new_tags}, 1 );
            $success++;
        }
    }

    if ( defined $retry_unmatched && $retry_unmatched eq "True" ) {
        for my $archive ( grep { $_->{tags} =~ /\b\Q$NO_GALLERY_TAG\E\b/ } @archives ) {
            sleep($interval);
            $logger->info("Retry ETagCN process: " . log_text( $archive->{title} ));
            $total++;

            my $plugin_result = run_metadata_plugin( $archive->{arcid} );
            if ( exists $plugin_result->{error} ) {
                $plugin_result->{error} = log_text( $plugin_result->{error} );
                $logger->warn("ETagCN plugin returned an error: " . $plugin_result->{error});
                next;
            }

            next unless exists $plugin_result->{new_tags};

            $plugin_result->{new_tags} = log_text( $plugin_result->{new_tags} );
            $logger->debug("Replace $NO_GALLERY_TAG with ETagCN tags: " . $plugin_result->{new_tags});
            my $new_tags = $archive->{tags};
            $new_tags =~ s/\b\Q$NO_GALLERY_TAG\E\b/$plugin_result->{new_tags}/g;
            set_tags( $archive->{arcid}, $new_tags, 0 );
            $success++;
        }
    }

    return ( modified => $success, total => $total );
}

1;
