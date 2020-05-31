#!/usr/bin/perl6

my %Found;	# book-abbr chap-number verse-number

# Internal Markup start and stop characters.
# As we convert from <XML> or <HTML>, we need our own markup using a different
# delimiter. Pick «» ($IMa and $IMb).
my $IMa = "«";
my $IMb = "»";
my $NOTES = "{$IMa}NOTES{$IMb}";	# footnotes
my $NOTEE = "{$IMa}NOTEE{$IMb}";
my $XREFS = "{$IMa}XREFS{$IMb}";	# cross reference
my $XREFE = "{$IMa}XREFE{$IMb}";
my $REFS = "{$IMa}REFS{$IMb}";	# reference within a footnote
my $REFE = "{$IMa}REFE{$IMb}";
my $ADDS = "{$IMa}ADDS{$IMb}";	# added text
my $ADDE = "{$IMa}ADDE{$IMb}";
my $ITS = "{$IMa}ITS{$IMb}";	# italics text
my $ITE = "{$IMa}ITE{$IMb}";
my $ALTS = "{$IMa}ALTS{$IMb}";	# alternate text
my $ALTE = "{$IMa}ALTE{$IMb}";
my $LABS = "{$IMa}LABS{$IMb}";	# label text
my $LABE = "{$IMa}LABE{$IMb}";
my $WOJS = "{$IMa}WOJS{$IMb}";	# words of Jesus
my $WOJE = "{$IMa}WOJE{$IMb}";
my $PS = "{$IMa}PS{$IMb}";	# paragraph
my $PE = "{$IMa}PE{$IMb}";
my $VPS = "{$IMa}VPS{$IMb}";	# published verse (often for different numbering)
my $VPE = "{$IMa}VPE{$IMb}";
my $LINEBREAK = "{$IMa}LINEBREAK{$IMb}";	# line break for quote or poetry
my $BLANK = "{$IMa}BLANK{$IMb}";	# blank line

#|(Convert different file formats into a theWord module.
Supported input formats: USFX
)
sub MAIN(
	Str $input where *.IO.f	#= existing file to convert into theWord module
) {
	my $content = $input.IO.slurp;
	my $parsed;
	if $content ~~ /^^ '<?xml' .* '?>' \s* '<usfx '/ {
		say "$input contains usfx";
		$parsed = parse-usfx($content, $input);
	}
	else {
		warn "$input format is not recognized";
	}
	# Should have populated %Found by now.
	# TODO: what if input has non-KJV verse numbering?
}

sub parse-usfx($input, $filename)
{
	my $bible-content = $input;
	my $book-abbr;
	my $book-content;
	while ($bible-content ~~ s/'<book' \s* $<book_attrs>=(<-[<>]>*) '>' $<content>=(.*?) '</book>'//) {
		$book-content = $<content>;
		say "book_attrs=$<book_attrs>";
		if $<book_attrs> ~~ /<|w> 'id="'(.*)'"'/ {
			$book-abbr = $0.Str;
			say "book-abbr=$book-abbr";
		}
		parse-usfx-book($book-abbr, $book-content);
	}
}

sub parse-usfx-book($book-abbr, $book-content)
{
	say "$book-abbr length={$book-content.chars}";
	my $chapter-number;
	for $book-content.split(/ '<c id="' \d+ '"' \s* '/>' /, :v) -> $c {
		my $verse-number;
		#say " c=$c";
		if $c ~~ /^'<c' \s+ 'id="' $<num>=(\d+) '"' \s* '/>'/ {
			$chapter-number = $<num>.Str;
		}
		elsif ($chapter-number.defined) {
			#say "chapter content {$c.chars} : {$c.substr(0,30)}";
			my $chapter = $c;
			$chapter ~~ s/ '<\/p>' $$ //;	# trailing </p> at very end of chapter.
			while $chapter ~~ s,
				'<v id="' $<num>=(\d+ <alpha>?) '"' \s* <-[<>]>* '/>' $<verse>=(.*?) '<ve' \s* '/>'
				,, {
					$verse-number = $<num>.Str;
					my $verse = $<verse>.Str;
					$verse = parse-usfx-verse($book-abbr, $chapter-number, $verse-number, $verse);
					save-verse($book-abbr, $chapter-number, $verse-number, $verse);
			}
		}
		else {
			#say "ignore stuff before chapter 1: $c";
		}
	}
}

sub parse-usfx-verse(Str $book-abbr, $chapter-number, $verse-number, Str $v)
{
	my $verse = $v;
	$verse ~~ s/'<ve' \s* '/>'//;
	$verse ~~ s/\n $//;
	# Convert to internal markup.
	$verse ~~ s:g[
		'<add' <|w> <-[<>]>* '>'
	       	$<text>=(.*?)
	       	'</add>'
	] = $ADDS ~ $<text> ~ $ADDE;
	$verse ~~ s:g@
		'<it' <|w> <-[<>]>* '>'
	       	$<text>=(.*?)
	       	'</it>'
		@$ITS$<text>$ITE@;
	$verse ~~ s:g@ '<b' \s* '/>' @@;
	$verse ~~ s:g@
		'</p>' \s* '<p>'
		@$PE$PS@;
	$verse ~~ s:g@
		'<vp' <|w> <-[<>]>* '>'
	       	$<text>=(.*?)
	       	'</vp>'
		@$VPS$<text>$VPE@;
	$verse ~~ s:g@
	       	'</q>' \s* '<q>'
		@$LINEBREAK@;
	$verse ~~ s:g[
		'<f' <|w> <-[<>]>* '>'
	       	$<footnote-body>=(.*?)
	       	'</f>'
	] = $NOTES ~ parse-usfx-footnote($<footnote-body>) ~ $NOTEE;
	$verse ~~ s:g[
		'<x' <|w> <-[<>]>* '>'
	       	$<xref-body>=(.*?)
	       	'</x>'
	] = $XREFS ~ parse-usfx-xref($<xref-body>) ~ $XREFE;
	return $verse;
}

sub parse-usfx-footnote($fn)
{
	my $footnote = $fn;
	# <fr>.*</fr> remove footnote reference
	$footnote ~~ s:g@
		'<fr' <|w> <-[<>]>* '>'
	       	.*?
	       	'</fr>'
		@@;
	# <ft>.*</ft> keep footnote text without the markers.
	$footnote ~~ s:g@
		'<ft' <|w> <-[<>]>* '>'
	       	$<text>=(.*?)
	       	'</ft>'
		@$<text>@;
	# <fqa>.*</fqa> keep footnote text without the markers.
	$footnote ~~ s:g@
		'<fqa' <|w> <-[<>]>* '>'
	       	$<text>=(.*?)
	       	'</fqa>'
		@$ALTS$<text>$ALTE@;
	$footnote ~~ s:g@
		'<it' <|w> <-[<>]>* '>'
	       	$<text>=(.*?)
	       	'</it>'
		@$ITS$<text>$ITE@;
	$footnote ~~ s:g@
		'<fl' <|w> <-[<>]>* '>'
	       	$<text>=(.*?)
	       	'</fl>'
		@$LABS$<text>$LABE@;
	# <ref>.*</ref> discard target reference and keep text.
	$footnote ~~ s:g@
		'<ref' \s+ 'tgt="' <-["<>]>* '">'
	       	$<text>=(.*?)
	       	'</ref>'
		@$<text>@;
	return $footnote;
}

sub parse-usfx-xref($n)
{
	my $note = $n;
	# <xo>.*</xo> remove xref reference
	$note ~~ s:g@
		'<xo' <|w> <-[<>]>* '>'
	       	.*?
	       	'</xo>'
		@@;
	# <ft>.*</ft> keep xref text without the markers.
	$note ~~ s:g@
		'<xt' <|w> <-[<>]>* '>'
	       	$<text>=(.*?)
	       	'</xt>'
		@$<text>@;
	# <ref>.*</ref> discard target reference and keep text.
	$note ~~ s:g@
		'<ref' \s+ 'tgt="' <-["<>]>* '">'
	       	$<text>=(.*?)
	       	'</ref>'
		@$<text>@;
	return $note;
}

sub save-verse(Str $book-abbr, $chapter-number, $verse-number, Str $v)
{
	my $verse = $v;
	say "$book-abbr $chapter-number:$verse-number $verse";
	%Found{$book-abbr}{$chapter-number}{$verse-number} = $verse;
}

