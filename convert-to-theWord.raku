#!/usr/bin/raku

my %Found;	# book-abbr chap-number verse-number
my @BookVerseCount;	# counts of verses in every (KJV) book of the Bible.
my %BibleVerseCount;	# counts of verses in OT, NT, and ONT (whole Bible)
my %BookAbbr2Index;	# map of book abbr to index into @BookVerseCount
my @EmitBookOrder;	# set after @BookVerseCount is populated
my %Emit;	# book-abbr chap-number verse-number
my %MetaData;	# book metadata, if we find it

my $dot-or-space = rx,[\s+ || \. \s* ],;
my $dot-or-colon-or-space = rx,[\s* <[.:\s]> \s*],;

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
my $ALTVS = "{$IMa}ALTVS{$IMb}";	# alternate verse numbering
my $ALTVE = "{$IMa}ALTVE{$IMb}";
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
	initialize();
	parse-meta($input);
	#say %MetaData;
	my $content = $input.IO.slurp;
	my $parsed;
	if $content ~~ /^^ '<?xml' .* '?>' \s* '<usfx '/ {
		#say "$input contains usfx";
		$parsed = parse-usfx($content, $input);
	}
	else {
		warn "$input format is not recognized";
	}
	adjust-lxx-numbering();
	emit-theWord();
}

sub parse-usfx($input, $filename)
{
	my $bible-content = $input;
	my $book-abbr;
	my $book-content;
	while ($bible-content ~~ s/'<book' \s* $<book_attrs>=(<-[<>]>*) '>' $<content>=(.*?) '</book>'//) {
		$book-content = $<content>;
		#say "book_attrs=$<book_attrs>";
		if $<book_attrs> ~~ /<|w> 'id="'(.*)'"'/ {
			$book-abbr = $0.Str;
			#say "book-abbr=$book-abbr";
		}
		parse-usfx-book($book-abbr, $book-content);
	}
}

sub parse-usfx-book($book-abbr, $book-content)
{
	#say "$book-abbr length={$book-content.chars}";
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
			# TODO handle <ve/><v id="6-8" bcv="EXO.40.6-8"/>
			# TODO handle <ve/><v id="10-11" bcv="EXO.40.10"/>
			# handle normal <ve/><v id="10" bcv="EXO.40.10"/>
			while $chapter ~~ s,
				'<v id="' $<id>=[\d+ <-["<>]>*] '"' \s+
				'bcv="' $<b>=[\w+] '.' $<c>=[\d+] '.' $<v>=[\d+ <-["<>]>*] '"' \s* <-[<>/]>* '/>' $<verse>=[.*?]
				'<ve' \s* '/>'
				,, {
					my $verse = $<verse>.Str;
					my $id = $<id>.Str;
					my $b = $<b>.Str;
					my $c = $<c>.Str;
					my $v = $<v>.Str;
					my $ide = '';
					my $ve = '';
					if $id ~~ s,\- $<ide>=[\d+]$,, {
						$ide = $<ide>.Str;
					}
					if $v ~~ s,\- $<ve>=[\d+]$,, {
						$ve = $<ve>.Str;
					}
					if ($id ne $v) {
						$*ERR.say("$b $c:$v != $id");
					}
					if $ide ne "" or $ve ne "" {
						$*ERR.say("$b $c:$v-$ve and $id-$ide");
					}
					if ($b eq "PSA" && $c == 118 && $v >= 175) {
						# Debug missing 118:176.
						$*ERR.say("$b $c:$v $verse");
					}
					$verse = parse-usfx-verse($b, $c, $v, $verse);
					%Found{$b}{$c}{$v} ~= $verse ~ "\n";
			}
			if $chapter ~~ m, '<v ' $<content>=[<-[<>]>*] '/>' , {
				$*ERR.say("<v with unparsed content: $<content>");
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
		'<ref' \s+ 'tgt="' $<target>=(<-[\""<>]>*) '">'
	       	.*?
	       	'</ref>'
		@$<target>@;
	return $footnote;
}

sub parse-usfx-xref($n)
{
	my $note = $n;
	# <xo>.*</xo> remove xref source reference
	$note ~~ s:g@
		'<xo' <|w> <-[<>]>* '>'
	       	.*?
	       	'</xo>'
		@@;
	# <xt>.*</xt> keep xref text without the markers.
	$note ~~ s:g@
		'<xt' <|w> <-[<>]>* '>'
	       	$<text>=(.*?)
	       	'</xt>'
		@$<text>@;
	# <ref>.*</ref> discard target reference and keep text.
	$note ~~ s:g@
		'<ref' \s+ 'tgt="' $<target>=(<-[\""<>]>*) '">'
	       	.*?
	       	'</ref>'
		@$<target>@;
	return $note.trim;
}

# If exists PSA.9.38 we have LXX with non-KJV numbering.
# LXX2012 does not have markup for alternate verse numbering.
# Patch up %Found to convert to KJV numbering.
# LXX Psa 9:21 - 146 numbering is different than KJV.
# Map Psa 9:21-38 -> 10:1-18, and 10-146 -> 11-147,
# and 147:1-9 -> 147:12-20.
sub adjust-lxx-numbering()
{
	if not %Found{'PSA'}{9}{38}:exists or %Found{'PSA'}{147}{20}:exists {
		warn "Not LXX numbering";
		return;
	}
	warn "Have LXX numbering";
	# TODO Exo 28:24 or so, missing 4 verses in LXXE.
	# TODO JOS.9.27-29 through JOS.9.33, KJV has only through v27.
	# Start from the end and work backward to avoid clobbering.
	for 9 ... 1 -> $v {
		%Found{'PSA'}{147}{$v+11} = "{$ALTVS}(147:$v)$ALTVE " ~ (%Found{'PSA'}{147}{$v}:delete);
	}
	for 146 ... 10 -> $c {
		if ($c == 118) {
			$*ERR.say("PSA.$c has {%Found{'PSA'}{$c}.elems} verses, last is {%Found{'PSA'}{$c}.keys.max}");
		}
		for %Found{'PSA'}{$c}.keys.max ... 1 -> $v {
			# $*ERR.say("PSA.$c.$v");
			if ($v >= 174) {
				$*ERR.say("move PSA.$c.$v");
			}
			if (!$v.defined ) {
				$*ERR.say("PSA.$c undefined verse $v");
			}
			elsif (%Found{'PSA'}{$c}:!exists) {
				$*ERR.say("PSA.$c not found");
			}
			elsif (%Found{'PSA'}{$c}{$v}:!exists) {
				$*ERR.say("PSA.$c:$v not found");
			}
			%Found{'PSA'}{$c+1}{$v} = "{$ALTVS}($c:$v)$ALTVE " ~ (%Found{'PSA'}{$c}{$v}:delete);
		}
	}
	for 9 ... 9 -> $c {
		for 38 ... 21 -> $v {
			%Found{'PSA'}{$c+1}{$v-20} = "{$ALTVS}($c:$v)$ALTVE " ~ (%Found{'PSA'}{$c}{$v}:delete);
		}
	}
}

sub emit-theWord()
{
	print "\c[BOM]";	# BOM byte order mark FEFF
	# Should have populated %Found by now.
	# If we have OT-only or NT-only, some books will be missing.
	#say '#keys in %Found ', %Found.keys.elems, ' keys: ', %Found.keys.join(' ');
	# TODO Walk the verses in theWord order and emit them.
	# in book order
	#say "emit-theWord";
	for @BookVerseCount[1..*] -> %book_info {
		#say %book_info;
		my $book-abbr = %book_info<short>;
		next unless %Found{$book-abbr}:exists;
		#say %book_info<full>;
		for 1 .. %book_info<chapters> -> $chapter-number {
			for 1 .. %book_info{$chapter-number} -> $verse-number {
				emit-verse($book-abbr, $chapter-number, $verse-number);
			}
		}
	}
	emit-epilog();
}

sub emit-epilog()
{
	say "";
	say "lang=%MetaData<lang>" if %MetaData<lang>:exists;
	say "short.title=%MetaData<abbreviation>" if %MetaData<abbreviation>:exists;
	say "description=%MetaData<description>" if %MetaData<description>:exists;
	say "about=%MetaData<about>" if %MetaData<about>:exists;
}

sub emit-verse($book-abbr, $chapter-number, $verse-number)
{
	my $text = %Found{$book-abbr}{$chapter-number}{$verse-number};
	if !$text.defined {
		$text = "(Any)";
		$*ERR.say("emit-verse missing $book-abbr $chapter-number:$verse-number");
	}
	$text ~~ s:g,\n, ,;
	$text ~~ s:g,$NOTES (.*?) $NOTEE,<RF>{$0}<Rf>,;
	$text ~~ s:g,$ADDS (.*?) $ADDE,<FI>{$0}<Fi>,;
	$text ~~ s:g,$ITS (.*?) $ITE,<i>{$0}</i>,;
	$text ~~ s:g,$LABS (.*?) $LABE,<i>{$0}</i>,;
	$text ~~ s:g,$ALTS (.*?) $ALTE,<FU>{$0}<Fu>,;	# alternate
	$text ~~ s:g,$ALTVS (.*?) $ALTVE,<font color=blue>{$0}</font>,;	# alternate verse
	$text ~~ s:g,$VPS (.*?) $VPE,<FU>{$0}<Fu>,;	# published verse #
	$text ~~ s:g,$PE $PS,<CM>,;
	$text ~~ s:g,$LINEBREAK,<CM>,;
	$text ~~ s:g,$XREFS (.*?) $XREFE,{translate-xref($0, '<RX ', '>')},;
	$text ~~ s:g,'  '+, ,;
	#say " ($book-abbr $chapter-number:$verse-number) $text";
	say $text;
}

# translate xref from {DEU.10.15 , Deu 10. 15.} to 5.10.15
# TODO Heb 12 29.
# TODO </xo><xt>Matt 15. 4. Eph 6. 1. </xt></x>
# TODO 1 Cor 10. 26, 28.
sub translate-xref($xref-ref, $element-start, $element-end)
{
	my $xref = $xref-ref;
	#say "xref[$xref]";
	my $result = '';
	while $xref ne "" {
		if $xref ~~ s,^\s+,, {
			next;
		}
		elsif $xref ~~ s,^\;,, {
			next;
		}
		elsif $xref ~~ s,^also \s+,, {
			next;
		}
		elsif $xref ~~ s,^$<book>=[[\d \s+]? <[A..Z]>\w\w*] $dot-or-space 
			$<chapter>=[\d+] $dot-or-colon-or-space
			$<verse>=[\d+] 
			[\s* $<range-sep>=<[-,]> \s* $<range-end>=\d+]? $dot-or-space? ,, {
		}
		else {
			warn "xref cannot parse book chapter. verses. from <$xref> from <$xref-ref>";
			last;
		}
		my $book = $<book>.Str.uc;
		my $chapter = $<chapter>.Str;
		my $verse = $<verse>.Str;
		my $range-sep = $<range-sep>:exists ?? $<range-sep>.Str !! "";
		my $range-end = $<range-end>:exists ?? $<range-end>.Str !! "";
		$book ~~ s:g/\s+//;
		my $booknum;
		if %BookAbbr2Index{$book}:exists {
			$booknum = %BookAbbr2Index{$book};
		}
		elsif %BookAbbr2Index{$book.substr(0,4)}:exists {
			$booknum = %BookAbbr2Index{$book.substr(0,4)};
		}
		elsif %BookAbbr2Index{$book.substr(0,3)}:exists {
			$booknum = %BookAbbr2Index{$book.substr(0,3)};
		}
		else {
			warn "xref no book number found for $book in $xref-ref";
		}
		my $new-xref = "$booknum.$chapter.$verse";
		if $range-sep eq "-" {
			$new-xref ~= "-$range-end";
		}
		elsif $range-sep eq "," && $verse.Int + 1 == $range-end.Int {
			# Treat Rom 4. 7,8 like Rom 4. 7-8.
			$new-xref ~= "-$range-end";
		}
		elsif $range-sep || $range-end {
			warn "xref must deal with range $range-sep $range-end for <$xref> from <$xref-ref>";
		}
		$*ERR.say: "xref ($xref-ref) -> ($new-xref)";
		$result ~= $element-start ~ $new-xref ~ $element-end;
	}
	return $result;
}

sub parse-meta($filename)
{
	my $metafile = $filename;
	$metafile ~~ s,_usfx,metadata,;
	if $metafile.IO:exists {
		my $meta = $metafile.IO.slurp;
		if $meta ~~ m,'<language>' $<language>=(.*?) '</language>', {
			if $<language> ~~ m,'<iso>' $<lang>=(.*?) '</iso>', {
				%MetaData<lang> = $<lang>.Str;
			}
		}
		if $meta ~~ m,'<identification>' $<identification>=(.*?) '</identification>', {
			my $identification = $<identification>.Str;
			if $identification ~~ m,'<nameLocal>' $<name>=(.*?) '</nameLocal>', {
				%MetaData<description> = $<name>.Str;
			}
			if $identification ~~ m,'<abbreviation>' $<short>=(.*?) '</abbreviation>', {
				%MetaData<short> = $<short>.Str;
			}
			if $identification ~~ m,'<description>' $<about>=(.*?) '</description>', {
				%MetaData<about> = $<about>.Str;
			}
		}
	}
}

sub initialize()
{
	@BookVerseCount := (
		{
			"chapters" => 0,
			"verses" => 0,
			"full" => "Ignore",
			"short" => "IGN",
			"pos" => 0,
		},
		{
			"full" => "Genesis",
			"short" => "GEN",
			"pos" => 1,
			"chapters" => 50,
			"verses" => 1533,
			1 => 31,
			2 => 25,
			3 => 24,
			4 => 26,
			5 => 32,
			6 => 22,
			7 => 24,
			8 => 22,
			9 => 29,
			10 => 32,
			11 => 32,
			12 => 20,
			13 => 18,
			14 => 24,
			15 => 21,
			16 => 16,
			17 => 27,
			18 => 33,
			19 => 38,
			20 => 18,
			21 => 34,
			22 => 24,
			23 => 20,
			24 => 67,
			25 => 34,
			26 => 35,
			27 => 46,
			28 => 22,
			29 => 35,
			30 => 43,
			31 => 55,
			32 => 32,
			33 => 20,
			34 => 31,
			35 => 29,
			36 => 43,
			37 => 36,
			38 => 30,
			39 => 23,
			40 => 23,
			41 => 57,
			42 => 38,
			43 => 34,
			44 => 34,
			45 => 28,
			46 => 34,
			47 => 31,
			48 => 22,
			49 => 33,
			50 => 26,
		},
		{
			"full" => "Exodus",
			"short" => "EXO",
			"pos" => 2,
			"chapters" => 40,
			"verses" => 1213,
			1 => 22,
			2 => 25,
			3 => 22,
			4 => 31,
			5 => 23,
			6 => 30,
			7 => 25,
			8 => 32,
			9 => 35,
			10 => 29,
			11 => 10,
			12 => 51,
			13 => 22,
			14 => 31,
			15 => 27,
			16 => 36,
			17 => 16,
			18 => 27,
			19 => 25,
			20 => 26,
			21 => 36,
			22 => 31,
			23 => 33,
			24 => 18,
			25 => 40,
			26 => 37,
			27 => 21,
			28 => 43,
			29 => 46,
			30 => 38,
			31 => 18,
			32 => 35,
			33 => 23,
			34 => 35,
			35 => 35,
			36 => 38,
			37 => 29,
			38 => 31,
			39 => 43,
			40 => 38,
		},
		{
			"full" => "Leviticus",
			"short" => "LEV",
			"pos" => 3,
			"chapters" => 27,
			"verses" => 859,
			1 => 17,
			2 => 16,
			3 => 17,
			4 => 35,
			5 => 19,
			6 => 30,
			7 => 38,
			8 => 36,
			9 => 24,
			10 => 20,
			11 => 47,
			12 => 8,
			13 => 59,
			14 => 57,
			15 => 33,
			16 => 34,
			17 => 16,
			18 => 30,
			19 => 37,
			20 => 27,
			21 => 24,
			22 => 33,
			23 => 44,
			24 => 23,
			25 => 55,
			26 => 46,
			27 => 34,
		},
		{
			"full" => "Numbers",
			"short" => "NUM",
			"pos" => 4,
			"chapters" => 36,
			"verses" => 1288,
			1 => 54,
			2 => 34,
			3 => 51,
			4 => 49,
			5 => 31,
			6 => 27,
			7 => 89,
			8 => 26,
			9 => 23,
			10 => 36,
			11 => 35,
			12 => 16,
			13 => 33,
			14 => 45,
			15 => 41,
			16 => 50,
			17 => 13,
			18 => 32,
			19 => 22,
			20 => 29,
			21 => 35,
			22 => 41,
			23 => 30,
			24 => 25,
			25 => 18,
			26 => 65,
			27 => 23,
			28 => 31,
			29 => 40,
			30 => 16,
			31 => 54,
			32 => 42,
			33 => 56,
			34 => 29,
			35 => 34,
			36 => 13,
		},
		{
			"full" => "Deuteronomy",
			"short" => "DEU",
			"pos" => 5,
			"chapters" => 34,
			"verses" => 959,
			1 => 46,
			2 => 37,
			3 => 29,
			4 => 49,
			5 => 33,
			6 => 25,
			7 => 26,
			8 => 20,
			9 => 29,
			10 => 22,
			11 => 32,
			12 => 32,
			13 => 18,
			14 => 29,
			15 => 23,
			16 => 22,
			17 => 20,
			18 => 22,
			19 => 21,
			20 => 20,
			21 => 23,
			22 => 30,
			23 => 25,
			24 => 22,
			25 => 19,
			26 => 19,
			27 => 26,
			28 => 68,
			29 => 29,
			30 => 20,
			31 => 30,
			32 => 52,
			33 => 29,
			34 => 12,
		},
		{
			"full" => "Joshua",
			"short" => "JOS",
			"pos" => 6,
			"chapters" => 24,
			"verses" => 658,
			1 => 18,
			2 => 24,
			3 => 17,
			4 => 24,
			5 => 15,
			6 => 27,
			7 => 26,
			8 => 35,
			9 => 27,
			10 => 43,
			11 => 23,
			12 => 24,
			13 => 33,
			14 => 15,
			15 => 63,
			16 => 10,
			17 => 18,
			18 => 28,
			19 => 51,
			20 => 9,
			21 => 45,
			22 => 34,
			23 => 16,
			24 => 33,
		},
		{
			"full" => "Judges",
			"short" => "JDG",
			"pos" => 7,
			"chapters" => 21,
			"verses" => 618,
			1 => 36,
			2 => 23,
			3 => 31,
			4 => 24,
			5 => 31,
			6 => 40,
			7 => 25,
			8 => 35,
			9 => 57,
			10 => 18,
			11 => 40,
			12 => 15,
			13 => 25,
			14 => 20,
			15 => 20,
			16 => 31,
			17 => 13,
			18 => 31,
			19 => 30,
			20 => 48,
			21 => 25,
		},
		{
			"full" => "Ruth",
			"short" => "RUT",
			"pos" => 8,
			"chapters" => 4,
			"verses" => 85,
			1 => 22,
			2 => 23,
			3 => 18,
			4 => 22,
		},
		{
			"full" => "First Book of Samuel",
			"short" => "1SA",
			"pos" => 9,
			"verses" => 810,
			"chapters" => 31,
			1 => 28,
			2 => 36,
			3 => 21,
			4 => 22,
			5 => 12,
			6 => 21,
			7 => 17,
			8 => 22,
			9 => 27,
			10 => 27,
			11 => 15,
			12 => 25,
			13 => 23,
			14 => 52,
			15 => 35,
			16 => 23,
			17 => 58,
			18 => 30,
			19 => 24,
			20 => 42,
			21 => 15,
			22 => 23,
			23 => 29,
			24 => 22,
			25 => 44,
			26 => 25,
			27 => 12,
			28 => 25,
			29 => 11,
			30 => 31,
			31 => 13,
		},
		{
			"full" => "Second Book of Samuel",
			"short" => "2SA",
			"pos" => 10,
			"verses" => 695,
			"chapters" => 24,
			1 => 27,
			2 => 32,
			3 => 39,
			4 => 12,
			5 => 25,
			6 => 23,
			7 => 29,
			8 => 18,
			9 => 13,
			10 => 19,
			11 => 27,
			12 => 31,
			13 => 39,
			14 => 33,
			15 => 37,
			16 => 23,
			17 => 29,
			18 => 33,
			19 => 43,
			20 => 26,
			21 => 22,
			22 => 51,
			23 => 39,
			24 => 25,
		},
		{
			"full" => "First Book of Kings",
			"short" => "1KI",
			"pos" => 11,
			"chapters" => 22,
			"verses" => 816,
			1 => 53,
			2 => 46,
			3 => 28,
			4 => 34,
			5 => 18,
			6 => 38,
			7 => 51,
			8 => 66,
			9 => 28,
			10 => 29,
			11 => 43,
			12 => 33,
			13 => 34,
			14 => 31,
			15 => 34,
			16 => 34,
			17 => 24,
			18 => 46,
			19 => 21,
			20 => 43,
			21 => 29,
			22 => 53,
		},
		{
			"full" => "Second Book of Kings",
			"short" => "2KI",
			"pos" => 12,
			"chapters" => 25,
			"verses" => 719,
			1 => 18,
			2 => 25,
			3 => 27,
			4 => 44,
			5 => 27,
			6 => 33,
			7 => 20,
			8 => 29,
			9 => 37,
			10 => 36,
			11 => 21,
			12 => 21,
			13 => 25,
			14 => 29,
			15 => 38,
			16 => 20,
			17 => 41,
			18 => 37,
			19 => 37,
			20 => 21,
			21 => 26,
			22 => 20,
			23 => 37,
			24 => 20,
			25 => 30,
		},
		{
			"full" => "First Book of Chronicles",
			"short" => "1CH",
			"pos" => 13,
			"chapters" => 29,
			"verses" => 942,
			1 => 54,
			2 => 55,
			3 => 24,
			4 => 43,
			5 => 26,
			6 => 81,
			7 => 40,
			8 => 40,
			9 => 44,
			10 => 14,
			11 => 47,
			12 => 40,
			13 => 14,
			14 => 17,
			15 => 29,
			16 => 43,
			17 => 27,
			18 => 17,
			19 => 19,
			20 => 8,
			21 => 30,
			22 => 19,
			23 => 32,
			24 => 31,
			25 => 31,
			26 => 32,
			27 => 34,
			28 => 21,
			29 => 30,
		},
		{
			"full" => "Second Book of Chronicles",
			"short" => "2CH",
			"pos" => 14,
			"chapters" => 36,
			"verses" => 822,
			1 => 17,
			2 => 18,
			3 => 17,
			4 => 22,
			5 => 14,
			6 => 42,
			7 => 22,
			8 => 18,
			9 => 31,
			10 => 19,
			11 => 23,
			12 => 16,
			13 => 22,
			14 => 15,
			15 => 19,
			16 => 14,
			17 => 19,
			18 => 34,
			19 => 11,
			20 => 37,
			21 => 20,
			22 => 12,
			23 => 21,
			24 => 27,
			25 => 28,
			26 => 23,
			27 => 9,
			28 => 27,
			29 => 36,
			30 => 27,
			31 => 21,
			32 => 33,
			33 => 25,
			34 => 33,
			35 => 27,
			36 => 23,
		},
		{
			"full" => "Ezra",
			"short" => "EZR",
			"pos" => 15,
			"chapters" => 10,
			"verses" => 280,
			1 => 11,
			2 => 70,
			3 => 13,
			4 => 24,
			5 => 17,
			6 => 22,
			7 => 28,
			8 => 36,
			9 => 15,
			10 => 44,
		},
		{
			"full" => "Nehemiah",
			"short" => "NEH",
			"pos" => 16,
			"chapters" => 13,
			"verses" => 406,
			1 => 11,
			2 => 20,
			3 => 32,
			4 => 23,
			5 => 19,
			6 => 19,
			7 => 73,
			8 => 18,
			9 => 38,
			10 => 39,
			11 => 36,
			12 => 47,
			13 => 31,
		},
		{
			"full" => "Esther",
			"short" => "EST",
			"pos" => 17,
			"chapters" => 10,
			"verses" => 167,
			1 => 22,
			2 => 23,
			3 => 15,
			4 => 17,
			5 => 14,
			6 => 14,
			7 => 10,
			8 => 17,
			9 => 32,
			10 => 3,
		},
		{
			"full" => "Job",
			"short" => "JOB",
			"pos" => 18,
			"chapters" => 42,
			"verses" => 1070,
			1 => 22,
			2 => 13,
			3 => 26,
			4 => 21,
			5 => 27,
			6 => 30,
			7 => 21,
			8 => 22,
			9 => 35,
			10 => 22,
			11 => 20,
			12 => 25,
			13 => 28,
			14 => 22,
			15 => 35,
			16 => 22,
			17 => 16,
			18 => 21,
			19 => 29,
			20 => 29,
			21 => 34,
			22 => 30,
			23 => 17,
			24 => 25,
			25 => 6,
			26 => 14,
			27 => 23,
			28 => 28,
			29 => 25,
			30 => 31,
			31 => 40,
			32 => 22,
			33 => 33,
			34 => 37,
			35 => 16,
			36 => 33,
			37 => 24,
			38 => 41,
			39 => 30,
			40 => 24,
			41 => 34,
			42 => 17,
		},
		{
			"full" => "Psalms",
			"short" => "PSA",
			"pos" => 19,
			"chapters" => 150,
			"verses" => 2461,
			1 => 6,
			2 => 12,
			3 => 8,
			4 => 8,
			5 => 12,
			6 => 10,
			7 => 17,
			8 => 9,
			9 => 20,
			10 => 18,
			11 => 7,
			12 => 8,
			13 => 6,
			14 => 7,
			15 => 5,
			16 => 11,
			17 => 15,
			18 => 50,
			19 => 14,
			20 => 9,
			21 => 13,
			22 => 31,
			23 => 6,
			24 => 10,
			25 => 22,
			26 => 12,
			27 => 14,
			28 => 9,
			29 => 11,
			30 => 12,
			31 => 24,
			32 => 11,
			33 => 22,
			34 => 22,
			35 => 28,
			36 => 12,
			37 => 40,
			38 => 22,
			39 => 13,
			40 => 17,
			41 => 13,
			42 => 11,
			43 => 5,
			44 => 26,
			45 => 17,
			46 => 11,
			47 => 9,
			48 => 14,
			49 => 20,
			50 => 23,
			51 => 19,
			52 => 9,
			53 => 6,
			54 => 7,
			55 => 23,
			56 => 13,
			57 => 11,
			58 => 11,
			59 => 17,
			60 => 12,
			61 => 8,
			62 => 12,
			63 => 11,
			64 => 10,
			65 => 13,
			66 => 20,
			67 => 7,
			68 => 35,
			69 => 36,
			70 => 5,
			71 => 24,
			72 => 20,
			73 => 28,
			74 => 23,
			75 => 10,
			76 => 12,
			77 => 20,
			78 => 72,
			79 => 13,
			80 => 19,
			81 => 16,
			82 => 8,
			83 => 18,
			84 => 12,
			85 => 13,
			86 => 17,
			87 => 7,
			88 => 18,
			89 => 52,
			90 => 17,
			91 => 16,
			92 => 15,
			93 => 5,
			94 => 23,
			95 => 11,
			96 => 13,
			97 => 12,
			98 => 9,
			99 => 9,
			100 => 5,
			101 => 8,
			102 => 28,
			103 => 22,
			104 => 35,
			105 => 45,
			106 => 48,
			107 => 43,
			108 => 13,
			109 => 31,
			110 => 7,
			111 => 10,
			112 => 10,
			113 => 9,
			114 => 8,
			115 => 18,
			116 => 19,
			117 => 2,
			118 => 29,
			119 => 176,
			120 => 7,
			121 => 8,
			122 => 9,
			123 => 4,
			124 => 8,
			125 => 5,
			126 => 6,
			127 => 5,
			128 => 6,
			129 => 8,
			130 => 8,
			131 => 3,
			132 => 18,
			133 => 3,
			134 => 3,
			135 => 21,
			136 => 26,
			137 => 9,
			138 => 8,
			139 => 24,
			140 => 13,
			141 => 10,
			142 => 7,
			143 => 12,
			144 => 15,
			145 => 21,
			146 => 10,
			147 => 20,
			148 => 14,
			149 => 9,
			150 => 6,
		},
		{
			"full" => "Proverbs",
			"short" => "PRO",
			"pos" => 20,
			"chapters" => 31,
			"verses" => 915,
			1 => 33,
			2 => 22,
			3 => 35,
			4 => 27,
			5 => 23,
			6 => 35,
			7 => 27,
			8 => 36,
			9 => 18,
			10 => 32,
			11 => 31,
			12 => 28,
			13 => 25,
			14 => 35,
			15 => 33,
			16 => 33,
			17 => 28,
			18 => 24,
			19 => 29,
			20 => 30,
			21 => 31,
			22 => 29,
			23 => 35,
			24 => 34,
			25 => 28,
			26 => 28,
			27 => 27,
			28 => 28,
			29 => 27,
			30 => 33,
			31 => 31,
		},
		{
			"full" => "Ecclesiastes",
			"short" => "ECC",
			"pos" => 21,
			"chapters" => 12,
			"verses" => 222,
			1 => 18,
			2 => 26,
			3 => 22,
			4 => 16,
			5 => 20,
			6 => 12,
			7 => 29,
			8 => 17,
			9 => 18,
			10 => 20,
			11 => 10,
			12 => 14,
		},
		{
			"full" => "Song of Solomon",
			"short" => "SNG",
			"pos" => 22,
			"chapters" => 8,
			"verses" => 117,
			1 => 17,
			2 => 17,
			3 => 11,
			4 => 16,
			5 => 16,
			6 => 13,
			7 => 13,
			8 => 14,
		},
		{
			"full" => "Isaiah",
			"short" => "ISA",
			"pos" => 23,
			"chapters" => 66,
			"verses" => 1292,
			1 => 31,
			2 => 22,
			3 => 26,
			4 => 6,
			5 => 30,
			6 => 13,
			7 => 25,
			8 => 22,
			9 => 21,
			10 => 34,
			11 => 16,
			12 => 6,
			13 => 22,
			14 => 32,
			15 => 9,
			16 => 14,
			17 => 14,
			18 => 7,
			19 => 25,
			20 => 6,
			21 => 17,
			22 => 25,
			23 => 18,
			24 => 23,
			25 => 12,
			26 => 21,
			27 => 13,
			28 => 29,
			29 => 24,
			30 => 33,
			31 => 9,
			32 => 20,
			33 => 24,
			34 => 17,
			35 => 10,
			36 => 22,
			37 => 38,
			38 => 22,
			39 => 8,
			40 => 31,
			41 => 29,
			42 => 25,
			43 => 28,
			44 => 28,
			45 => 25,
			46 => 13,
			47 => 15,
			48 => 22,
			49 => 26,
			50 => 11,
			51 => 23,
			52 => 15,
			53 => 12,
			54 => 17,
			55 => 13,
			56 => 12,
			57 => 21,
			58 => 14,
			59 => 21,
			60 => 22,
			61 => 11,
			62 => 12,
			63 => 19,
			64 => 12,
			65 => 25,
			66 => 24,
		},
		{
			"full" => "Jeremiah",
			"short" => "JER",
			"pos" => 24,
			"chapters" => 52,
			"verses" => 1364,
			1 => 19,
			2 => 37,
			3 => 25,
			4 => 31,
			5 => 31,
			6 => 30,
			7 => 34,
			8 => 22,
			9 => 26,
			10 => 25,
			11 => 23,
			12 => 17,
			13 => 27,
			14 => 22,
			15 => 21,
			16 => 21,
			17 => 27,
			18 => 23,
			19 => 15,
			20 => 18,
			21 => 14,
			22 => 30,
			23 => 40,
			24 => 10,
			25 => 38,
			26 => 24,
			27 => 22,
			28 => 17,
			29 => 32,
			30 => 24,
			31 => 40,
			32 => 44,
			33 => 26,
			34 => 22,
			35 => 19,
			36 => 32,
			37 => 21,
			38 => 28,
			39 => 18,
			40 => 16,
			41 => 18,
			42 => 22,
			43 => 13,
			44 => 30,
			45 => 5,
			46 => 28,
			47 => 7,
			48 => 47,
			49 => 39,
			50 => 46,
			51 => 64,
			52 => 34,
		},
		{
			"full" => "Lamentations",
			"short" => "LAM",
			"pos" => 25,
			"chapters" => 5,
			"verses" => 154,
			1 => 22,
			2 => 22,
			3 => 66,
			4 => 22,
			5 => 22,
		},
		{
			"full" => "Ezekiel",
			"short" => "EZK",
			"pos" => 26,
			"chapters" => 48,
			"verses" => 1273,
			1 => 28,
			2 => 10,
			3 => 27,
			4 => 17,
			5 => 17,
			6 => 14,
			7 => 27,
			8 => 18,
			9 => 11,
			10 => 22,
			11 => 25,
			12 => 28,
			13 => 23,
			14 => 23,
			15 => 8,
			16 => 63,
			17 => 24,
			18 => 32,
			19 => 14,
			20 => 49,
			21 => 32,
			22 => 31,
			23 => 49,
			24 => 27,
			25 => 17,
			26 => 21,
			27 => 36,
			28 => 26,
			29 => 21,
			30 => 26,
			31 => 18,
			32 => 32,
			33 => 33,
			34 => 31,
			35 => 15,
			36 => 38,
			37 => 28,
			38 => 23,
			39 => 29,
			40 => 49,
			41 => 26,
			42 => 20,
			43 => 27,
			44 => 31,
			45 => 25,
			46 => 24,
			47 => 23,
			48 => 35,
		},
		{
			"full" => "Daniel",
			"short" => "DAN",
			"pos" => 27,
			"chapters" => 12,
			"verses" => 357,
			1 => 21,
			2 => 49,
			3 => 30,
			4 => 37,
			5 => 31,
			6 => 28,
			7 => 28,
			8 => 27,
			9 => 27,
			10 => 21,
			11 => 45,
			12 => 13,
		},
		{
			"full" => "Hosea",
			"short" => "HOS",
			"pos" => 28,
			"chapters" => 14,
			"verses" => 197,
			1 => 11,
			2 => 23,
			3 => 5,
			4 => 19,
			5 => 15,
			6 => 11,
			7 => 16,
			8 => 14,
			9 => 17,
			10 => 15,
			11 => 12,
			12 => 14,
			13 => 16,
			14 => 9,
		},
		{
			"full" => "Joel",
			"short" => "JOL",
			"pos" => 29,
			"chapters" => 3,
			"verses" => 73,
			1 => 20,
			2 => 32,
			3 => 21,
		},
		{
			"full" => "Amos",
			"short" => "AMO",
			"pos" => 30,
			"chapters" => 9,
			"verses" => 146,
			1 => 15,
			2 => 16,
			3 => 15,
			4 => 13,
			5 => 27,
			6 => 14,
			7 => 17,
			8 => 14,
			9 => 15,
		},
		{
			"full" => "Obadiah",
			"short" => "OBA",
			"pos" => 31,
			"chapters" => 1,
			"verses" => 21,
			1 => 21,
		},
		{
			"full" => "Jonah",
			"short" => "JON",
			"pos" => 32,
			"chapters" => 4,
			"verses" => 48,
			1 => 17,
			2 => 10,
			3 => 10,
			4 => 11,
		},
		{
			"full" => "Micah",
			"short" => "MIC",
			"pos" => 33,
			"chapters" => 7,
			"verses" => 105,
			1 => 16,
			2 => 13,
			3 => 12,
			4 => 13,
			5 => 15,
			6 => 16,
			7 => 20,
		},
		{
			"full" => "Nahum",
			"short" => "NAM",
			"pos" => 34,
			"chapters" => 3,
			"verses" => 47,
			1 => 15,
			2 => 13,
			3 => 19,
		},
		{
			"full" => "Habakkuk",
			"short" => "HAB",
			"pos" => 35,
			"chapters" => 3,
			"verses" => 56,
			1 => 17,
			2 => 20,
			3 => 19,
		},
		{
			"full" => "Zephaniah",
			"short" => "ZEP",
			"pos" => 36,
			"chapters" => 3,
			"verses" => 53,
			1 => 18,
			2 => 15,
			3 => 20,
		},
		{
			"full" => "Haggai",
			"short" => "HAG",
			"pos" => 37,
			"chapters" => 2,
			"verses" => 38,
			1 => 15,
			2 => 23,
		},
		{
			"full" => "Zechariah",
			"short" => "ZEC",
			"pos" => 38,
			"chapters" => 14,
			"verses" => 211,
			1 => 21,
			2 => 13,
			3 => 10,
			4 => 14,
			5 => 11,
			6 => 15,
			7 => 14,
			8 => 23,
			9 => 17,
			10 => 12,
			11 => 17,
			12 => 14,
			13 => 9,
			14 => 21,
		},
		{
			"full" => "Malachi",
			"short" => "MAL",
			"pos" => 39,
			"chapters" => 4,
			"verses" => 55,
			1 => 14,
			2 => 17,
			3 => 18,
			4 => 6,
		},
		{
			"full" => "Matthew",
			"short" => "MAT",
			"pos" => 40,
			"chapters" => 28,
			"verses" => 1071,
			1 => 25,
			2 => 23,
			3 => 17,
			4 => 25,
			5 => 48,
			6 => 34,
			7 => 29,
			8 => 34,
			9 => 38,
			10 => 42,
			11 => 30,
			12 => 50,
			13 => 58,
			14 => 36,
			15 => 39,
			16 => 28,
			17 => 27,
			18 => 35,
			19 => 30,
			20 => 34,
			21 => 46,
			22 => 46,
			23 => 39,
			24 => 51,
			25 => 46,
			26 => 75,
			27 => 66,
			28 => 20,
		},
		{
			"full" => "Mark",
			"short" => "MRK",
			"pos" => 41,
			"chapters" => 16,
			"verses" => 678,
			1 => 45,
			2 => 28,
			3 => 35,
			4 => 41,
			5 => 43,
			6 => 56,
			7 => 37,
			8 => 38,
			9 => 50,
			10 => 52,
			11 => 33,
			12 => 44,
			13 => 37,
			14 => 72,
			15 => 47,
			16 => 20,
		},
		{
			"full" => "Luke",
			"short" => "LUK",
			"pos" => 42,
			"chapters" => 24,
			"verses" => 1151,
			1 => 80,
			2 => 52,
			3 => 38,
			4 => 44,
			5 => 39,
			6 => 49,
			7 => 50,
			8 => 56,
			9 => 62,
			10 => 42,
			11 => 54,
			12 => 59,
			13 => 35,
			14 => 35,
			15 => 32,
			16 => 31,
			17 => 37,
			18 => 43,
			19 => 48,
			20 => 47,
			21 => 38,
			22 => 71,
			23 => 56,
			24 => 53,
		},
		{
			"full" => "John",
			"short" => "JHN",
			"pos" => 43,
			"chapters" => 21,
			"verses" => 879,
			1 => 51,
			2 => 25,
			3 => 36,
			4 => 54,
			5 => 47,
			6 => 71,
			7 => 53,
			8 => 59,
			9 => 41,
			10 => 42,
			11 => 57,
			12 => 50,
			13 => 38,
			14 => 31,
			15 => 27,
			16 => 33,
			17 => 26,
			18 => 40,
			19 => 42,
			20 => 31,
			21 => 25,
		},
		{
			"full" => "Acts",
			"short" => "ACT",
			"pos" => 44,
			"chapters" => 28,
			"verses" => 1007,
			1 => 26,
			2 => 47,
			3 => 26,
			4 => 37,
			5 => 42,
			6 => 15,
			7 => 60,
			8 => 40,
			9 => 43,
			10 => 48,
			11 => 30,
			12 => 25,
			13 => 52,
			14 => 28,
			15 => 41,
			16 => 40,
			17 => 34,
			18 => 28,
			19 => 41,
			20 => 38,
			21 => 40,
			22 => 30,
			23 => 35,
			24 => 27,
			25 => 27,
			26 => 32,
			27 => 44,
			28 => 31,
		},
		{
			"full" => "Romans",
			"short" => "ROM",
			"pos" => 45,
			"chapters" => 16,
			"verses" => 434,
			1 => 32,
			2 => 29,
			3 => 31,
			4 => 25,
			5 => 21,
			6 => 23,
			7 => 25,
			8 => 39,
			9 => 33,
			10 => 21,
			11 => 36,
			12 => 21,
			13 => 14,
			14 => 23,	# differs 26
			15 => 33,
			16 => 27,	# differs 25
		},
		{
			"full" => "1 Corinthians",
			"short" => "1CO",
			"pos" => 46,
			"chapters" => 16,
			"verses" => 437,
			1 => 31,
			2 => 16,
			3 => 23,
			4 => 21,
			5 => 13,
			6 => 20,
			7 => 40,
			8 => 13,
			9 => 27,
			10 => 33,
			11 => 34,
			12 => 31,
			13 => 13,
			14 => 40,
			15 => 58,
			16 => 24,
		},
		{
			"full" => "2 Corinthians",
			"short" => "2CO",
			"pos" => 47,
			"chapters" => 13,
			"verses" => 257,
			1 => 24,
			2 => 17,
			3 => 18,
			4 => 18,
			5 => 21,
			6 => 18,
			7 => 16,
			8 => 24,
			9 => 15,
			10 => 18,
			11 => 33,
			12 => 21,
			13 => 14,
		},
		{
			"full" => "Galatians",
			"short" => "GAL",
			"pos" => 48,
			"chapters" => 6,
			"verses" => 149,
			1 => 24,
			2 => 21,
			3 => 29,
			4 => 31,
			5 => 26,
			6 => 18,
		},
		{
			"full" => "Ephesians",
			"short" => "EPH",
			"pos" => 49,
			"chapters" => 6,
			"verses" => 155,
			1 => 23,
			2 => 22,
			3 => 21,
			4 => 32,
			5 => 33,
			6 => 24,
		},
		{
			"full" => "Philippians",
			"short" => "PHP",
			"pos" => 50,
			"chapters" => 4,
			"verses" => 104,
			1 => 30,
			2 => 30,
			3 => 21,
			4 => 23,
		},
		{
			"full" => "Colossians",
			"short" => "COL",
			"pos" => 51,
			"chapters" => 4,
			"verses" => 95,
			1 => 29,
			2 => 23,
			3 => 25,
			4 => 18,
		},
		{
			"full" => "1 Thessalonians",
			"short" => "1TH",
			"pos" => 52,
			"chapters" => 5,
			"verses" => 89,
			1 => 10,
			2 => 20,
			3 => 13,
			4 => 18,
			5 => 28,
		},
		{
			"full" => "2 Thessalonians",
			"short" => "2TH",
			"pos" => 53,
			"chapters" => 3,
			"verses" => 47,
			1 => 12,
			2 => 17,
			3 => 18,
		},
		{
			"full" => "1 Timothy",
			"short" => "1TI",
			"pos" => 54,
			"chapters" => 6,
			"verses" => 113,
			1 => 20,
			2 => 15,
			3 => 16,
			4 => 16,
			5 => 25,
			6 => 21,
		},
		{
			"full" => "2 Timothy",
			"short" => "2TI",
			"pos" => 55,
			"chapters" => 4,
			"verses" => 83,
			1 => 18,
			2 => 26,
			3 => 17,
			4 => 22,
		},
		{
			"full" => "Titus",
			"short" => "TIT",
			"pos" => 56,
			"chapters" => 3,
			"verses" => 46,
			1 => 16,
			2 => 15,
			3 => 15,
		},
		{
			"full" => "Philemon",
			"short" => "PHM",
			"pos" => 57,
			"chapters" => 1,
			"verses" => 25,
			1 => 25,
		},
		{
			"full" => "Hebrews",
			"short" => "HEB",
			"pos" => 58,
			"chapters" => 13,
			"verses" => 303,
			1 => 14,
			2 => 18,
			3 => 19,
			4 => 16,
			5 => 14,
			6 => 20,
			7 => 28,
			8 => 13,
			9 => 28,
			10 => 39,
			11 => 40,
			12 => 29,
			13 => 25,
		},
		{
			"full" => "James",
			"short" => "JAS",
			"pos" => 59,
			"chapters" => 5,
			"verses" => 108,
			1 => 27,
			2 => 26,
			3 => 18,
			4 => 17,
			5 => 20,
		},
		{
			"full" => "1 Peter",
			"short" => "1PE",
			"pos" => 60,
			"chapters" => 5,
			"verses" => 105,
			1 => 25,
			2 => 25,
			3 => 22,
			4 => 19,
			5 => 14,
		},
		{
			"full" => "2 Peter",
			"short" => "2PE",
			"pos" => 61,
			"chapters" => 3,
			"verses" => 61,
			1 => 21,
			2 => 22,
			3 => 18,
		},
		{
			"full" => "1 John",
			"short" => "1JN",
			"pos" => 62,
			"chapters" => 5,
			"verses" => 105,
			1 => 10,
			2 => 29,
			3 => 24,
			4 => 21,
			5 => 21,
		},
		{
			"full" => "2 John",
			"short" => "2JN",
			"pos" => 63,
			"chapters" => 1,
			"verses" => 13,
			1 => 13,
		},
		{
			"full" => "3 John",
			"short" => "3JN",
			"pos" => 64,
			"chapters" => 1,
			"verses" => 14,
			1 => 14,
		},
		{
			"full" => "Jude",
			"short" => "JUD",
			"pos" => 65,
			"chapters" => 1,
			"verses" => 25,
			1 => 25,
		},
		{
			"full" => "Revelation",
			"short" => "REV",
			"pos" => 66,
			"chapters" => 22,
			"verses" => 404,
			1 => 20,
			2 => 29,
			3 => 22,
			4 => 11,
			5 => 14,
			6 => 17,
			7 => 17,
			8 => 13,
			9 => 21,
			10 => 11,
			11 => 19,
			12 => 17,
			13 => 18,
			14 => 20,
			15 => 8,
			16 => 21,
			17 => 18,
			18 => 24,
			19 => 21,
			20 => 15,
			21 => 27,
			22 => 21,
		},
	);
	%BibleVerseCount := {
		'ot' => 23145,
		'nt' => 7958,
		'ont' => 31103,
		};
	#say "@BookVerseCount keys ordered ", @BookVerseCount.map: *.<short>;
	for 1 .. @BookVerseCount.end -> $i {
		%BookAbbr2Index{@BookVerseCount[$i]<short>} = $i;
		my $full = @BookVerseCount[$i]<full>;
		%BookAbbr2Index{$full} = $i;
		$full = $full.uc;
		%BookAbbr2Index{$full} = $i;
		$full ~~ s:g/\s+//;
		%BookAbbr2Index{$full} = $i;
		$full = $full.substr(0,3);
		%BookAbbr2Index{$full} = $i;
	}
	#say "%BookAbbr2Index : ", %BookAbbr2Index;
	#@EmitBookOrder = sort { $BookVerseCount{$a}{pos} <=> $BookVerseCount{$b}{pos} } grep (!/^\./, keys %{$BookVerseCount});
}

