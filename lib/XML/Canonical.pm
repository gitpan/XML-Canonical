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
use constant XMLNS_NS => 'http://www.w3.org/2000/xmlns/';

use vars qw($VERSION %char_entities);

use Data::Dumper;

$VERSION = '0.05';

%char_entities = ( 
		  '&' => '&amp;',
		  '<' => '&lt;',
		  '>' => '&gt;',
		  '"' => '&quot;',
		  "\x09" => '&#x9;',
		  "\x0a" => '&#xA;',
		  "\x0d" => '&#xD;'
		 );

use XML::GDOME;
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
  my $doc = XML::GDOME->createDocFromString($string, GDOME_LOAD_SUBSTITUTE_ENTITIES | GDOME_LOAD_COMPLETE_ATTRS);
  $string = $self->canonicalize_document($doc);
  return $string;
}

sub canonicalize_document {
  my ($self, $doc) = @_;
  my @nodes = $self->{comments} ?  $doc->findnodes(XPATH_C14N_WITH_COMMENTS) :
    $doc->findnodes(XPATH_C14N_OMIT_COMMENTS );
  $self->{visible_nodes} = {};
  for (@nodes) {
    $self->{visible_nodes}->{$_->gdome_ref} = 1;
  }
#  $doc->setEncoding("UTF-8");
  $self->process($doc);
  $self->remove_ns_attrs();
  return $self->{output};
}

sub canonicalize_nodes {
  my ($self, $doc, $nodes) = @_;
  delete $self->{visible_nodes};
  delete $self->{output};
  for (@$nodes) {
    $self->{visible_nodes}->{$_->gdome_ref} = 1;
  }
#  $doc->setEncoding("UTF-8");
  $self->process($doc);
  $self->remove_ns_attrs();
  return $self->{output};
}

sub print {
  my ($self, $string) = @_;
  $self->{output} .= $string;
}

sub process {
  my ($self, $node, $is_document_element) = @_;

  my $type = $node->getNodeType;

  if ($type == GDOME_ENTITY_REFERENCE_NODE) {
    my $nl = $node->getChildNodes;
    for my $i (0 .. $nl->getLength - 1) {
      $self->process($nl->item("$i"));
    }
  } elsif ($type == GDOME_ENTITY_NODE) {
    warn "entity node";
  } elsif ($type == GDOME_ATTRIBUTE_NODE) {
    die "illegal node";
  } elsif ($type == GDOME_TEXT_NODE || $type == GDOME_CDATA_SECTION_NODE) {
    if ($self->engine_visible($node)) {
      $self->print(normalize_text($node->getNodeValue));
    }
  } elsif ($type == GDOME_COMMENT_NODE) {
    if ($self->engine_visible($node)) {
      if ($self->{processing_pos} == AFTER_DOCUMENT_ELEM) {
	$self->print("\n");
      }
      $self->print("<!--".normalize_comment($node->getNodeValue)."-->");
      if ($self->{processing_pos} == BEFORE_DOCUMENT_ELEM) {
	$self->print("\n");
      }
    }
  } elsif ($type == GDOME_PROCESSING_INSTRUCTION_NODE) {
    if ($self->engine_visible($node)) {
      if ($self->{processing_pos} == AFTER_DOCUMENT_ELEM) {
	$self->print("\n");
      }
      $self->print("<?" . $node->getTarget);
      my $s = $node->getData;
      if (length($s) > 0) {
	$self->print(" " . normalize_pi($s));
      }
      $self->print("?>");
      if ($self->{processing_pos} == BEFORE_DOCUMENT_ELEM) {
	$self->print("\n");
      }
    }
  } elsif ($type == GDOME_ELEMENT_NODE) {
    $self->{processing_pos} = INSIDE_DOCUMENT_ELEM if $is_document_element;
    # XXX - put in a check for relative namespaces
    check_for_relative_namespace($node);

    if ($self->engine_visible($node)) {
      $self->print("<" . $node->getTagName());
      $self->process_xml_attributes($node);
      $self->process_namespaces($node);
      my $nnm = $node->getAttributes;
      my @attrs;
      for my $i (0 .. $nnm->getLength - 1) {
        push @attrs, $nnm->item("$i");
      }
      for my $attr (sort attr_compare @attrs) {
	if ($self->engine_visible($attr)) {
          my $normalized_attr = normalize_attr($attr->getNodeValue);
	  $normalized_attr = '' unless defined($normalized_attr);
	  $self->print(' ' . $attr->getName . '="' . $normalized_attr . '"');
	}
      }
      $self->print(">");
    }
    my $nl = $node->getChildNodes;
    for my $i (0 .. $nl->getLength - 1) {
      $self->process($nl->item("$i"));
    }
    if ($self->engine_visible($node)) {
      $self->print("</" . $node->getTagName() . ">");
      $self->{processing_pos} = AFTER_DOCUMENT_ELEM if $is_document_element;
    }
  } elsif ($type == GDOME_DOCUMENT_NODE) {
    my $nl = $node->getChildNodes;
    for my $i (0 .. $nl->getLength - 1) {
      $self->process($nl->item("$i"),1);
    }
  }
}

# Iterates over all Attributes which have been added during c14n and
# removes them
sub remove_ns_attrs {
  my ($self) = @_;
  for (@{$self->{attrs_to_be_removed_after_c14n}}) {
#    print "$_";
#    print $_->toString;
#    print "hi 3 " . $_ . "\n";
#    print "hi 2 " . $_->getValue . "\n";
    my $ownerElem = $_->getOwnerElement;
#    print "=====================================\n";
#    print $ownerElem->toString;
#    print "\n";
#    print $ownerElem->getName . "\n";
#    print "hi2 " . $_->getName . "\n";
    $ownerElem->removeAttribute($_->getName);
  }
}

sub engine_visible {
  my ($self, $node) = @_;
  return exists $self->{visible_nodes}->{$node->gdome_ref};
}

sub engine_make_invisible {
  my ($self, $node) = @_;
  delete $self->{visible_nodes}->{$node->gdome_ref};
}

sub engine_make_visible {
  my ($self, $node) = @_;
  $self->{visible_nodes}->{$node->gdome_ref} = 1;
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
  $s =~ s/([\x09\x0a\x0d&<"])/$char_entities{$1}/ge if defined($s); #"
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
  my $nnm = $node->getAttributes;
  for my $i (0 .. $nnm->getLength - 1) {
    my $attr = $nnm->item("$i");
    my $node_attr_name = $attr->getName();
    if ($node_attr_name eq 'xmlns' || $node_attr_name =~ /^xmlns:/){
      # assume empty namespaces are absolute
      my $attr_value = $attr->getNodeValue;
      return 1 unless $attr_value;
      unless ($attr_value =~ m!^\w+://[\w.]+!){
	my $name = $node->getTagName;
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
    last if $parent_node->getNodeType != GDOME_ELEMENT_NODE;
    push @parent_nodes, $parent_node;
  }
  return \@parent_nodes;
}

sub process_xml_attributes {
  my ($self, $node) = @_;
  my $parent_nodes = $self->get_ancestor_elements($node);

  my %used_xml_attributes;
  for my $parent_node (@$parent_nodes) {
    my $nnm = $parent_node->getAttributes;
    for my $i (0 .. $nnm->getLength - 1) {
      my $attr = $nnm->item("$i");
      my $name = $attr->getName;
      $used_xml_attributes{$name} = 1 if $name =~ m!^xml:!;
    }
  }

  for my $attr_name (keys %used_xml_attributes) {
    my $ctx_attr_value;
    my ($attr_local_name) = ($attr_name =~ m!^xml:(.*)!);
    if (length($node->getAttributeNS(XML_NS,$attr_local_name)) == 0) {
      for my $parent_node (@$parent_nodes) {
	my $attr_value;
	# XXX: getAttribute doesn't work here...
	my $v = $parent_node->getAttributeNS(XML_NS,$attr_local_name);
        $attr_value = $v if defined($v);
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
      $node->setAttributeNS(XML_NS, $attr_name, $ctx_attr_value);
      my $attr = $node->getAttributeNodeNS(XML_NS,$attr_local_name);
      $self->engine_make_visible($node->getAttributeNodeNS(XML_NS,$attr_local_name));
    }
  }
}

sub process_namespaces {
  my ($self, $ctx_node) = @_;

  return unless $self->engine_visible($ctx_node);

  if ($ctx_node->getNodeType != GDOME_ELEMENT_NODE) {
    die "process_namespaces called on non-element";
  }

  my $ctx_attributes = $ctx_node->getAttributes;

  for my $i (0 .. $ctx_attributes->getLength - 1) {
    my $node_attr = $ctx_attributes->item("$i");
    my $node_attr_name = $node_attr->getNodeName;
    my $node_attr_value = $node_attr->getValue;
    my $defines_default_ns = ($node_attr_name eq 'xmlns');
    my $defines_arbitrary_ns = ($node_attr_name =~ m!xmlns:!);

    if ($defines_default_ns) {
      my $attr_value_empty = (length($node_attr_value) == 0);

      if (!$attr_value_empty) {
        # case 1
        my $a = $self->find_first_visible_default_ns_attr($ctx_node);

        if (defined($a)) {
          if ($node_attr_value eq $a->getValue) {
            $self->engine_make_invisible($node_attr);
          }
        }
      } else {
        # case 2
        my $a = $self->find_first_visible_default_ns_attr($ctx_node);

        if (defined($a)) {
          if (length($a->getValue) == 0) {
            $self->engine_make_invisible($node_attr);
          }
        } else {
          $self->engine_make_invisible($node_attr);
        }
      }
    } elsif ($defines_arbitrary_ns) {
      my $attr_value_empty = (length($node_attr_value) == 0);

      if (!$attr_value_empty) {
        # case 3
        my $a = $self->find_first_visible_non_default_ns_attr($ctx_node, $node_attr_name);

        if (defined($a)) {
          if ($node_attr_value eq $a->getValue) {
            $self->engine_make_invisible($node_attr);
          }
        }
      } else {
        # case 4

        # todo check what we have to do here
      }
    }
  }

  # TODO
  # if hidden parent nodes have default namespace, 
  # make sure that we include them
  my $invis_def_ns = $self->find_first_invisible_default_ns_attr($ctx_node);
  if (defined($invis_def_ns)) {
    if (length($invis_def_ns->getValue) != 0) {
      # case 5
      my $vis_def_ns = $self->find_first_visible_default_ns_attr($ctx_node);

      if (defined($vis_def_ns)) {
        if ($invis_def_ns->getValue ne $vis_def_ns->getValue) {
	  $ctx_node->setAttribute("xmlns", $invis_def_ns->getValue);
	  my $new_attr = $ctx_node->getAttributeNode("xmlns");
          $self->engine_make_visible($new_attr);
          push @{$self->{attrs_to_be_removed_after_c14n}}, $new_attr;
        }
      } else {
        unless ($ctx_node->hasAttribute("xmlns")) {
	  $ctx_node->setAttribute("xmlns", $invis_def_ns->getValue);
	  my $new_attr = $ctx_node->getAttributeNode("xmlns");
          $self->engine_make_visible($new_attr);
          push @{$self->{attrs_to_be_removed_after_c14n}}, $new_attr;
        }
      }
    } else {
      # case 6
      my $vis_def_ns = $self->find_first_visible_default_ns_attr($ctx_node);
      if (defined($vis_def_ns)) {
        if ($invis_def_ns->getValue ne $vis_def_ns->getValue) {
          $ctx_node->setAttribute("xmlns", $invis_def_ns->getValue);
	  my $new_attr = $ctx_node->getAttributeNode("xmlns");
          $self->engine_make_visible($new_attr);
          push @{$self->{attrs_to_be_removed_after_c14n}}, $new_attr;
        }
      }
    }
  }
  # include any non-default namespaces from invisible parent nodes
  my $invis_ns = $self->find_invisible_non_default_ns_attrs($ctx_node);
  while (my ($invis_attr_localName, $invis_attr) = each %$invis_ns) {
    if (length($invis_attr->getValue) != 0) {
      # case 7
      my $vis_attr = $self->find_first_visible_non_default_ns_attr($ctx_node, "xmlns:" . $invis_attr_localName);

      if (defined($vis_attr)) {
        if ($invis_attr->getValue ne $vis_attr->getValue) {
          $ctx_node->setAttributeNS(XMLNS_NS, "xmlns:" . $invis_attr_localName, $invis_attr->getValue);
	  my $new_attr = $ctx_node->getAttributeNodeNS(XMLNS_NS, $invis_attr_localName);
          $self->engine_make_visible($new_attr);
          push @{$self->{attrs_to_be_removed_after_c14n}}, $new_attr;
        }
      } else {
	$ctx_node->setAttributeNS(XMLNS_NS, "xmlns:" . $invis_attr_localName, $invis_attr->getValue);
	my $new_attr = $ctx_node->getAttributeNodeNS(XMLNS_NS, $invis_attr_localName);
	$self->engine_make_visible($new_attr);
	push @{$self->{attrs_to_be_removed_after_c14n}}, $new_attr;
      }
    } else {
      # case 8
    }
  }
}

sub find_first_visible_default_ns_attr {
  my ($self, $node) = @_;

  while ($node = $node->getParentNode) {
    last if $node->getNodeType != GDOME_ELEMENT_NODE;
    next unless $self->engine_visible($node);
    my $attr = $node->getAttributeNode("xmlns");
    return $attr if defined($attr);
  }
}

sub find_first_visible_non_default_ns_attr {
  my ($self, $node, $name) = @_;

  my $localName = (split(':',$name))[1];

  while ($node = $node->getParentNode) {
    last if $node->getNodeType != GDOME_ELEMENT_NODE;
    next unless $self->engine_visible($node);
    my $attr = $node->getAttributeNodeNS(XMLNS_NS, $localName);
    return $attr if defined($attr);
  }
}

sub find_first_invisible_default_ns_attr {
  my ($self, $node) = @_;

  while ($node = $node->getParentNode) {
    last if $node->getNodeType != GDOME_ELEMENT_NODE;
    last if $self->engine_visible($node);
    my $attr = $node->getAttributeNode("xmlns");
    return $attr if defined($attr);
  }
}

sub find_invisible_non_default_ns_attrs {
  my ($self, $node) = @_;

  my %invis_ns;

  while ($node = $node->getParentNode) {
    last if $node->getNodeType != GDOME_ELEMENT_NODE;
    last if $self->engine_visible($node);
    my $nnm = $node->getAttributes;
    for my $i (0 .. $nnm->getLength - 1) {
      my $attr = $nnm->item("$i");
      my $name = $attr->getName;
      next unless $name =~ m!^xmlns:(.*)!;
      my $localName = $1;
      $invis_ns{$localName} = $attr
          unless exists $invis_ns{$localName};
    }
  }
  return \%invis_ns;
}

1;
__END__

=head1 NAME

XML::Canonical - Perl Implementation of Canonical XML

=head1 SYNOPSIS

  use XML::Canonical;
  $canon = XML::Canonical->new(comments => 1);
  $canon_xml = $canon->canonicalize_string($xml_string);
  $canon_xml = $canon->canonicalize_document($xmlgdome_document);

  my @nodes = $doc->findnodes(qq{(//*[local-name()='included'] | //@*)});
  my $canon_output = $canon->canonicalize_nodes($doc, \@nodes);

=head1 DESCRIPTION

This module provides an implementation of Canonical XML Recommendation
(Version 1, 15 March 2001).  It uses L<XML::GDOME> for its DOM tree and
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

Reads in a XML::GDOME::Document object and an array reference to
a set of visible nodes returns the canonical form of the selected nodes.

=back

=head1 TODO

Support for XML Signature and upcoming XML Encryption.  See
http://www.w3.org/Signature/  The interface should be similar to
the Apache XML Security package, to make it easy to switch between
the packages.

=head1 NOTES

This module is in early alpha stage.  It is suggested that you look over
the source code and test cases before using the module.  In addition,
the API is subject to change.

This module implements the lastest w3 recommendation, located at
http://www.w3.org/TR/2001/REC-xml-c14n-20010315

Parts are adapted from the Apache XML Security package.
See http://xml.apache.org/security/

Comments, suggestions, and patches welcome.

=head1 AUTHOR

T.J. Mather, E<lt>tjmather@tjmather.comE<gt>

=head1 COPYRIGHT

Copyright (c) 2001, 2002 T.J. Mather.  XML::Canonical is free software;
you may redistribute it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<XML::GDOME>, L<XML::Handler::CanonXMLWriter>.

=cut
