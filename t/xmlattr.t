# tests for xml attributes

use XML::Canonical;

print "1..5\n";

my $i = 1;

my $input1 = "<included    xml:lang='de'>" .
	     "<notIncluded xml:lang='de'>" . 
	     "<notIncluded xml:lang='uk'>" . 
	     "<included                 >" .
	     "</included>" .
	     "</notIncluded>" . 
	     "</notIncluded>" .
	     "</included>";

my $output1 = "<included xml:lang=\"de\">" .
	      "<included xml:lang=\"uk\">" .
	      "</included>" .
	      "</included>";

test_xml_attributes($input1, $output1);

my $input2 = "<included    xml:lang='uk'>" .
             "<notIncluded xml:lang='de'>" .
             "<notIncluded xml:lang='uk'>" .
             "<included                 >" .
             "</included>" .
             "</notIncluded>" .
             "</notIncluded>" .
             "</included>";

my $output2 = "<included xml:lang=\"uk\">" .
              "<included>" .
              "</included>" .
              "</included>";

test_xml_attributes($input2, $output2);

my $input3 = "<included    xml:lang='de'>" .
             "<notIncluded xml:lang='de'>" .
             "<notIncluded xml:lang='uk'>" .
             "<included    xml:lang='de'>" .
             "</included>" .
             "</notIncluded>" .
             "</notIncluded>" .
             "</included>";
 
my $output3 = "<included xml:lang=\"de\">" .
              "<included>" .
              "</included>" .
              "</included>";

test_xml_attributes($input3, $output3);

my $input4 = "<included    xml:lang='de'>" .
             "<included    xml:lang='de'>" .
             "<notIncluded xml:lang='uk'>" .
             "<included                 >" .
             "</included>" .
             "</notIncluded>" .
             "</included>" .
             "</included>";

my $output4 = "<included xml:lang=\"de\">" .
              "<included>" .
              "<included xml:lang=\"uk\">" .
              "</included>" .
              "</included>" .
              "</included>";

test_xml_attributes($input4, $output4);

my $input5 = "<included                         xml:lang='de'>" .
             "<included                         xml:lang='de'>" .
             "<notIncluded xml:space='preserve' xml:lang='uk'>" .
             "<included                 >" .
             "</included>" .
             "</notIncluded>" .
             "</included>" .
             "</included>";
 
my $output5 = "<included xml:lang=\"de\">" .
              "<included>" .
              "<included xml:lang=\"uk\" xml:space=\"preserve\">" .
              "</included>" .
              "</included>" .
              "</included>";

test_xml_attributes($input5, $output5);

sub test_xml_attributes {
  my ($input, $canon_expect) = @_;

  my $parser = XML::LibXML->new();
  my $doc = $parser->parse_string($input);
  my @nodes = $doc->findnodes(qq{(//*[local-name()='included'] | //@*)});

  my $canon = XML::Canonical->new(comments => 0);
  my $canon_output = $canon->canonicalize_nodes($doc, \@nodes);
  print "not " unless $canon_expect eq $canon_output;
  print "ok $i\n";
  $i++;
}
