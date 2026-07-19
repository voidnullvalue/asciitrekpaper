use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Temp qw(tempfile);

# The embedded, cross-compiled Perl on-device has no system @INC at all: it
# only ever sees the two directories the JNI layer passes to perl_parse (see
# app/src/main/cpp/asciitrek_jni.c). If Asciitrek::Engine (or anything it
# uses) pulls in a core module that isn't copied into
# app/src/main/assets/perl/lib by native/build_perl_android.sh, the engine
# loads fine under the *system* perl running this test suite (which has the
# full core library available) but fails to load on the real device. Run a
# child perl with @INC hard-restricted to exactly those two directories to
# catch that gap here instead of on a phone.

my $root = File::Spec->rel2abs('app/src/main/assets/perl');
my $lib  = File::Spec->catdir($root, 'lib');

plan skip_all => "bundled Perl assets not found at $root" unless -d $root;

my ($fh, $child_script) = tempfile(SUFFIX => '.pl', UNLINK => 1);
print {$fh} <<'PERL';
BEGIN { @INC = ($ARGV[0], $ARGV[1]); }
use Asciitrek::Engine;
my $engine = Asciitrek::Engine->new(columns => 80, rows => 24, seed => 1);
$engine->tick_frame(0.05) for 1 .. 3;
print "OK\n";
PERL
close $fh;

my $output = `"$^X" "$child_script" "$root" "$lib" 2>&1`;
is($?, 0, 'Asciitrek::Engine loads and runs with only the bundled asset dirs on @INC')
    or diag($output);
like($output, qr/OK/, 'engine produced a frame with the restricted @INC');

done_testing;
