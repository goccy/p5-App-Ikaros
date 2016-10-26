package App::Ikaros::IO;
use strict;
use warnings;

sub read {
    my ($filename) = @_;
    open my $fh, '<', $filename or die $!;
    my $content = do { local $/; <$fh> };
    close $fh or die $!;
    return $content;
}

sub write {
    my ($filename, $content) = @_;
    open my $fh, '>', $filename or die $!;
    print $fh $content;
    close $fh or die $!;
}

1;
