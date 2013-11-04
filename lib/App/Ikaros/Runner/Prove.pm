package App::Ikaros::Runner::Prove;

use strict;
use warnings;
use App::Prove;

my $app = App::Prove->new;
$app->process_args(@ARGV);
exit( $app->run ? 0 : 1 );

1;
