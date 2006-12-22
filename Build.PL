use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Set::IntSpan::Fast',
    license             => 'perl',
    dist_author         => 'Andy Armstrong <andy@hexten.net>',
    dist_version_from   => 'lib/Set/IntSpan/Fast.pm',
    requires => {
        'Test::More'    => 0,
        'version'       => 0,
        'Class::Std'    => 0,
        'Data::Types'   => 0,
        'List::Util'    => 0,
    },
    add_to_cleanup      => [ 'Set-IntSpan-Fast-*' ],
);

$builder->create_build_script();
