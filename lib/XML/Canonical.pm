package XML::Canonical;

use strict;
use warnings;
use constant BEFORE_DOCUMENT_ELEM => 0;
use constant INSIDE_DOCUMENT_ELEM => 1;
use constant AFTER_DOCUMENT_ELEM => 2;
use constant XPATH_C14N_WITH_COMMENTS => '(//. | //@* | //namespace::*)';
use constant XPATH_C14N_OMIT_COMMENTS =>
               XPATH_C14N_WITH_COMMENTS . '[not(self::comment())]';
use constant XML_NS => 'http://www.w3.org/XML/1998/namespace';

use vars qw($VERSION %char_entities);
$VERSION = '0.02';

%char_entities = ( 
		  '&' => '&amp;',
		  '<' => '&lt;',
		  '>' => '&gt;',
		  '"' => '&quot;',
		  "\x09" => '&#x9;',
		  "\x0a" => '&#xA;',
		  "\x0d" => '&#xD;'
		 );

use XML::LibXML;
use Data::Dumper;

sub new {
  my ($class, %opt) = @_;
  my $comments = (exists $opt{comments} && $opt{comments}) ? 1 : 0;
  my $self = bless { comments => $comments }, $class;
  $self->{processing_pos} = BEFORE_DOCUMENT_ELEM;
  return $self;
}

sub canonicalize_string {
  my ($self, $string) = @_;
  my $parser = XML::LibXML->new();
  my $doc = $parser->parse_string($string);
  return $self->canonicalize_document($doc);
}

sub canonicalize_document {
  my ($self, $doc) = @_;
  my @nodes = $self->{comments} ?  $doc->findnodes(XPATH_C14N_WITH_COMMENTS) :
    $doc->findnodes(XPATH_C14N_OMIT_COMMENTS );
  $self->{visible_nodes} = {};
  for (@nodes) {
    $self->{visible_nodes}->{$_->getPointer} = 1;
  }
  $doc->setEncoding("UTF-8");
  $self->process($doc);
  return $self->{output};
}

sub canonicalize_nodes {
  my ($self, $doc, $nodes) = @_;
  $self->{visible_nodes} = {};
  for (@$nodes) {
    $self->{visible_nodes}->{$_->getPointer} = 1;
  }
  $doc->setEncoding("UTF-8");
  $self->process($doc);
  return $self->{output};
}

sub print {
  my ($self, $string) = @_;
  $self->{output} .= $string;
}

sub process {
  my ($self, $node, $is_document_element) = @_;

  my $type = $node->getType;

  if ($type == XML_ENTITY_REF_NODE) {
    for ($node->getChildnodes) {
      $self->process($_);
    }
  } elsif ($type == XML_ENTITY_NODE) {
    warn "entity node";
  } elsif ($type == XML_ATTRIBUTE_NODE) {
    die "illegal node";
  } elsif ($type == XML_TEXT_NODE || $type == XML_CDATA_SECTION_NODE) {
    if ($self->engine_visible($node)) {
      $self->print(normalize_text($node->getData));
    }
  } elsif ($type == XML_COMMENT_NODE) {
    if ($self->engine_visible($node)) {
      if ($self->{processing_pos} == AFTER_DOCUMENT_ELEM) {
	$self->print("\n");
      }
      $self->print("<!--".normalize_comment($node->getData)."-->");
      if ($self->{processing_pos} == BEFORE_DOCUMENT_ELEM) {
	$self->print("\n");
      }
    }
  } elsif ($type eq XML_PI_NODE) {
    if ($self->engine_visible($node)) {
      if ($self->{processing_pos} == AFTER_DOCUMENT_ELEM) {
	$self->print("\n");
      }
      $self->print("<?" . $node->getName);
      my $s = $node->getData;
      if (length($s) > 0) {
	$self->print(" " . normalize_pi($s));
      }
      $self->print("?>");
      if ($self->{processing_pos} == BEFORE_DOCUMENT_ELEM) {
	$self->print("\n");
      }
    }
  } elsif ($type == XML_ELEMENT_NODE) {
    $self->{processing_pos} = INSIDE_DOCUMENT_ELEM if $is_document_element;
    # XXX - put in a check for relative namespaces
    check_for_relative_namespace($node);

    if ($self->engine_visible($node)) {
      $self->print("<" . $node->getName());
      $self->process_xml_attributes($node);
      $self->process_namespaces($node);
      for my $attr (sort attr_compare $node->getAttributes) {
	$self->print(' ' . $attr->getName . '="' . normalize_attr($attr->getData) . '"')
	  if ($self->engine_visible($attr));
      }
      $self->print(">");
    }
    for ($node->getChildnodes) {
      $self->process($_);
    }
    if ($self->engine_visible($node)) {
      $self->print("</" . $node->getName() . ">");
      $self->{processing_pos} = AFTER_DOCUMENT_ELEM if $is_document_element;
    }
  } elsif ($type == XML_DOCUMENT_NODE) {
    for ($node->getChildnodes) {
      $self->process($_,1);
    }
  }
}

sub engine_visible {
  my ($self, $node) = @_;
  return exists $self->{visible_nodes}->{$node->getPointer};
}

sub engine_make_invisible {
  my ($self, $node) = @_;
  delete $self->{visible_nodes}->{$node->getPointer};
}

sub engine_make_visible {
  my ($self, $node) = @_;
  $self->{visible_nodes}->{$node->getPointer} = 1;
}

sub attr_compare {
  my $name0 = $a->getName;
  my $name1 = $b->getName;
  my $prefix0 = $a->getPrefix;
  my $prefix1 = $b->getPrefix;
  my $local_name0 = $a->getLocalName;
  my $local_name1 = $b->getLocalName;
  my $namespace_URI0 = $a->getNamespaceURI || '';
  my $namespace_URI1 = $b->getNamespaceURI || '';
  my $definesNS0 = 0;
  my $definesNS1 = 0;
  my $defines_defaultNS0 = 0;
  my $defines_defaultNS1 = 0;

  if ($name0 eq 'xmlns') {
    $local_name0 = '';
    $prefix0 = 'xmlns';
    $definesNS0 = 1;
    $defines_defaultNS0 = 1;
    $namespace_URI0 ||= 'http://www.w3.org/2000/xmlns/';
  }
  if ($name1 eq 'xmlns') {
    $local_name1 = '';
    $prefix1 = 'xmlns';
    $definesNS1 = 1;
    $defines_defaultNS1 = 1;
    $namespace_URI1 ||= 'http://www.w3.org/2000/xmlns/';
  }
  if ($name0 =~ /^xmlns:(.*)/){
    $prefix0 = 'xmlns';
    $local_name0 = $1;
    $definesNS0 = 1;
    $namespace_URI0 ||= 'http://www.w3.org/2000/xmlns/';
  }
  if ($name1 =~ /^xmlns:(.*)/){
    $prefix1 = 'xmlns';
    $local_name1 = $1;
    $definesNS1 = 1;
    $namespace_URI1 ||= 'http://www.w3.org/2000/xmlns/';
  }
  $local_name0 = $name0 unless $namespace_URI0;
  $local_name1 = $name1 unless $namespace_URI1;

  if ($definesNS0 && $definesNS1) {
    return $local_name0 cmp $local_name1;
  } elsif (!$definesNS0 && !$definesNS1) {
    my $NS_comparison_result = ($namespace_URI0 cmp $namespace_URI1);
    return $NS_comparison_result if $NS_comparison_result != 0;
    return $local_name0 cmp $local_name1;
  } elsif ($definesNS0 && !$definesNS1) {
    # namespace nodes come before other nodes
    return -1;
  } else {
    return 1;
  }
}

sub normalize_attr {
  my ($s) = @_;
  $s =~ s/([\x09\x0a\x0d&<"])/$char_entities{$1}/ge; #"
  return $s;
}

*normalize_comment = \&normalize_pi;

sub normalize_pi {
  my ($s) = @_;
  $s =~ s/([\x0d])/$char_entities{$1}/ge;
  return $s;
}

sub normalize_text {
  my ($s) = @_;
  $s =~ s/([\x0d&<>])/$char_entities{$1}/ge;
  return $s;
}

sub check_for_relative_namespace {
  my ($node) = @_;
  for my $attr ($node->getAttributes) {
    my $node_attr_name = $attr->getName();
    if ($node_attr_name eq 'xmlns' || $node_attr_name =~ /^xmlns:/){
      # assume empty namespaces are absolute
      my $attr_value = $attr->getData;
      return 1 unless $attr_value;
      unless ($attr_value =~ m!^\w+://[\w.]+!){
	my $name = $node->getName;
	die qq{Relative namespace for <$name $node_attr_name="$attr_value">};
      }
    }
  }
}

sub get_ancestor_elements {
  my ($self, $node) = @_;
  my $parent_node = $node;
  my @parent_nodes;
  while ($parent_node = $parent_node->getParentNode) {
    last if $parent_node->getType != XML_ELEMENT_NODE;
    push @parent_nodes, $parent_node;
  }
  return \@parent_nodes;
}

sub process_xml_attributes {
  my ($self, $node) = @_;
  my $parent_nodes = $self->get_ancestor_elements($node);

  my %used_xml_attributes;
  for my $parent_node (@$parent_nodes) {
    for my $attr ($parent_node->getAttributes) {
      my $name = $attr->getName;
      $used_xml_attributes{$name} = 1 if $name =~ m!^xml:!;
    }
  }

  for my $attr_name (keys %used_xml_attributes) {
    my $ctx_attr_value;
    my ($attr_local_name) = ($attr_name =~ m!^xml:(.*)!);
    if (!defined($node->getAttributeNS(XML_NS,$attr_local_name))) {
      for my $parent_node (@$parent_nodes) {
	my $attr_value;
	# XXX: getAttribute doesn't work here...
	for ($parent_node->getAttributes) {
	  $attr_value = $_->getValue if $_->getName eq $attr_name;
	}
	if (!$self->engine_visible($parent_node) && !defined($ctx_attr_value)) {
	  $ctx_attr_value = $attr_value;
	} elsif ($self->engine_visible($parent_node) && defined($ctx_attr_value)
		&& defined($attr_value)) {
	  if ($ctx_attr_value eq $attr_value) {
	    $ctx_attr_value = undef;
	  }
	  last;
	}
      }
    } else {
      $ctx_attr_value = $node->getAttributeNS(XML_NS,$attr_local_name);
      for my $parent_node (@$parent_nodes) {
	if ($self->engine_visible($parent_node) &&
	    defined($parent_node->getAttributeNS(XML_NS,$attr_local_name))) {
	  if ($ctx_attr_value eq $parent_node->getAttributeNS(XML_NS,$attr_local_name)) {
	    $ctx_attr_value = undef;
	    # delete orig attr XXX
	    $self->engine_make_invisible($node->getAttributeNodeNS(XML_NS,$attr_local_name));
	  }
	  last;
	}
      }
    }
    if (defined($ctx_attr_value)) {
      $node->setAttributeNS(XML_NS,$attr_name, $ctx_attr_value);
      $self->engine_make_visible($node->getAttributeNodeNS(XML_NS,$attr_local_name));
    }
  }
}

sub process_namespaces {
  my ($self, $node) = @_;
  for my $node_ns ($node->getNamespaces) {
    my $node_ns_prefix = $node_ns->prefix || '';
    my $node_ns_value = $node_ns->getValue;

    if ($node_ns_prefix eq '') {
      my $parent_node = $node;
      while ($parent_node = $parent_node->getParentNode) {
	if ($parent_node->getType != XML_ELEMENT_NODE) {
	  if (length($node_ns_value) == 0) {
            $self->engine_make_invisible($node_ns);
          }
          last;
        }
	if (my $ns = $parent_node->getNamespace("")) {
	  if (length($node_ns_value) != 0) {
	    # case 1
	    if ($node_ns_value eq $ns->getValue) {
	      $self->engine_make_invisible($node_ns);
	    }
	  } else {
	    # case 2
	    if (length($ns->getValue) == 0) {
	      $self->engine_make_invisible($node_ns);
	    }
	  }
          last;
	}
      }
    } else {
      if ( length($node_ns_value) > 0) {
	# case 3
	my $parent_node = $node;
	while ($parent_node = $parent_node->getParentNode) {
	  last if $parent_node->getType != XML_ELEMENT_NODE;
          # XXX: get rid of xmlns: prefix
	  if (my $ns = $parent_node->getNamespace($node_ns_prefix)) {
	    if ($node_ns_value eq $ns->getValue) {
	      $self->engine_make_invisible($node_ns);
	      last;
	    }
	  }
	}
      } else {
	# case 4
      }
    }
  }
  # if hidden parent nodes have default namespace, 
  # make sure that we include them
  unless ($node->getNamespace("")) {
    my $parent_node = $node;
    while ($parent_node = $parent_node->getParentNode) {
      last if $parent_node->getType != XML_ELEMENT_NODE;
      last if $self->engine_visible($parent_node);
      if (my $invis_ns = $parent_node->getNamespace("")) {
	my $visible_parent_node = $parent_node;
	my $visible_ns;
	while ($visible_parent_node = $visible_parent_node->getParentNode) {
	  last if $visible_parent_node->getType != XML_ELEMENT_NODE;
	  next unless $self->engine_visible($visible_parent_node);
	  last if $visible_ns = $visible_parent_node->getNamespace("");
	}
	my $invis_ns_value = $invis_ns->getValue;
	if (length($invis_ns_value) != 0) {
	  # case 5
	  unless ($visible_ns &&
		  $visible_ns->getValue eq $invis_ns_value) {
	    $node->setAttribute("xmlns", $invis_ns_value);
	    $self->engine_make_visible($node->getNamespace(""));
	  }
	} else {
	  # case 6
	  if ($visible_ns &&
	      $visible_ns->getValue ne $invis_ns_value) {
	    $node->setAttribute("xmlns", $invis_ns_value);
	    $self->engine_make_visible($node->getNamespace(""));
	  }
	}
      }
    }
  }
  # include any non-default namespaces from invisible parent nodes
  my $parent_node = $node;
  my %invis_ns;
  my %vis_ns;
  while ($parent_node = $parent_node->getParentNode) {
    last if $parent_node->getType != XML_ELEMENT_NODE;
    last if $self->engine_visible($parent_node);
    for my $ns ( $parent_node->getNamespaces ) {
      my $ns_prefix = $ns->prefix;
      if (length($ns_prefix) > 0){
	$invis_ns{$ns_prefix} = $ns->getValue
	  unless exists $invis_ns{$ns_prefix};
      }
    }
  }
  $parent_node = $node;
  while ($parent_node = $parent_node->getParentNode) {
    last if $parent_node->getType != XML_ELEMENT_NODE;
    next unless $self->engine_visible($parent_node);
    for my $ns ( $parent_node->getNamespaces ) {
      my $ns_prefix = $ns->prefix || '';
      if (length($ns_prefix) > 0) {
	$vis_ns{$ns_prefix} = $ns->getValue
	  unless exists $vis_ns{$ns_prefix};
      }
    }
  }
  while (my ($invis_ns_prefix, $invis_ns_value) = each %invis_ns) {
    if (length($invis_ns_value) > 0) {
      # case 7
      unless (exists $vis_ns{$invis_ns_prefix} &&
	      $vis_ns{$invis_ns_prefix} eq $invis_ns_value) {
	unless ($node->getNamespace($invis_ns_prefix)) {
	  $node->setAttribute(
            'xmlns' . ($invis_ns_prefix ? ":$invis_ns_prefix" : ""),
            $invis_ns_value);
	  $self->engine_make_visible($node->getNamespace($invis_ns_prefix));
	}
      }
    } else {
      # case 8

    }
  }
}

1;
__END__

=head1 NAME

XML::Canonical - Perl Implementation of Canonical XML

=head1 SYNOPSIS

  use XML::Canonical;
  $canon = XML::Canonical->new(comments => 1);
  $canon_xml = $canon->canonicalize_string($xml_string);
  $canon_xml = $canon->canonicalize_document($libxml_document);

  my @nodes = $doc->findnodes(qq{(//*[local-name()='included'] | //@*)});
  my $canon_output = $canon->canonicalize_nodes($doc, \@nodes);

=head1 DESCRIPTION

This modules provides an implementation of Canonical XML Recommendation
(Version 1, 15 March 2001).  It uses L<XML::LibXML> for its DOM tree and
XPath nodes.

=head1 METHODS

=over 4

=item $canon = XML::Canonical->new( comments => $comments );

Returns a new XML::Canonical object.  If $comments is 1, then the
canonical output will include comments, otherwise comments will be
removed from the output.

=item $output = $canon->canonicalize_string( $xml_string );

Reads in an XML string and outputs its canonical form.

=item $output = $canon->canonicalize_document( $libxml_doc );

Reads in a XML::LibXML::Document object and returns its canonical form.

=item $output = $canon->canonicalize_nodes( $libxml_doc, $nodes );

Reads in a XML::LibXML::Document object and an array reference to
a set of visible nodes returns the canonical form of the selected nodes.

=back

=head1 NOTES

This module is in early alpha stage.  It is suggested that you look over
the source code and test cases before using the module.  In addition,
the API is subject to change.

In furture versions, XML::GDOME may be used for the DOM tree and
XPath.  See http://tjmather.com/xml-gdome/ for details.

This module implements the lastest w3 recommendation, located at
http://www.w3.org/TR/2001/REC-xml-c14n-20010315

Parts are adapted from the Apache XML Security package.
See http://www.xmlsecurity.org

Comments, suggestions, and patches welcome.

=head1 AUTHOR

T.J. Mather, E<lt>tjmather@tjmather.comE<gt>

=head1 COPYRIGHT

Copyright (c) 2001 T.J. Mather.  XML::Canonical is free software;
you may redistribute it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<XML::LibXML>, L<XML::CanonXMLWriter>.

=cut
