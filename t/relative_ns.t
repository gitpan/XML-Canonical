# tests for xml attributes

use XML::Canonical;

print "1..2\n";

my $input1 = "<absolute:correct      xmlns:absolute='http://www.absolute.org/#likeVodka'>" .
             "<relative:incorrect    xmlns:relative='../cheating#away'>" .
             "</relative:incorrect>" .
             "</absolute:correct>" .
             "\n";

my $parser = XML::LibXML->new();
my $doc = $parser->parse_string($input1);
my $canon = XML::Canonical->new(comments => 0);
eval {
  my $canon_output = $canon->canonicalize_document($doc);
};
print "not " unless $@ =~ m!Relative namespace for!;
print "ok 1\n";

my $input2 = "<absolute:correct      xmlns:absolute='http://www.absolute.org/#likeVodka'>" .
             "<relative:incorrect    xmlns:relative='../cheating#away'>" .
             "</relative:incorrect>" .
             "</absolute:correct>";

$parser = XML::LibXML->new();
$doc = $parser->parse_string($input1);
my @nodes = $doc->findnodes(qq{//self::*[local-name()='absolute']});

eval {
  my $canon_output = $canon->canonicalize_nodes($doc, \@nodes);
};
print "not " unless $@ =~ m!Relative namespace for!;
print "ok 2\n";
