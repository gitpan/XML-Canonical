# tests for examples in w3 recommendation

use XML::Canonical;

print "1..7\n";

for my $i (1..6) {
  my $input = slurp("t/in/3${i}_input.xml");
  my $canon_expect = slurp("t/in/3${i}_c14n.xml");
  chomp($canon_expect);
  my $canon = XML::Canonical->new(comments => 0);
  my $canon_output = $canon->canonicalize_string($input);
  print "not " unless $canon_expect eq $canon_output;
  print "ok $i\n";
}

my $input = slurp("t/in/31_input.xml");
my $canon_expect = slurp("t/in/31_c14n-comments.xml");
chomp($canon_expect);
my $canon = XML::Canonical->new(comments => 1);
my $canon_output = $canon->canonicalize_string($input);
print "not " unless $canon_expect eq $canon_output;
print "ok 7\n";

# we currently don't test this b/c XML::LibXML doesn't have
# support for setting namespaces in xpath context
#my $input = slurp("t/in/37_input.xml");
#my $canon_expect = slurp("t/in/37_c14n.xml");
#chomp($canon_expect);
#my $parser = XML::LibXML->new();
#my $doc = $parser->parse_string($input);
#my @nodes = $doc->findnodes(qq{(//. | //@* | //namespace::*) [ self::ietf:e1 or (parent::ietf:e1 and not(self::text() or self::e2)) or count(id("E3")|ancestor-or-self::node()) = count(ancestor-or-self::node()) ]});
#my $canon = XML::Canonical->new(comments => 0);
#my $canon_output = $canon->canonicalize_nodes(\@nodes);
#print "not " unless $canon_expect eq $canon_output;
#print "ok 7\n";
#print "got $canon_output\n\nexpected $canon_expect\n";

sub slurp {
  my ($filename) = @_;
  my $text;
  open F, "$filename";
  while(<F>){
    $text .= $_;
  }
  close F;
  chomp($text);
  return $text;
}
