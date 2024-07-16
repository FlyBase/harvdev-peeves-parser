# Code to parse gene proformae

use strict;

our (%fsm, $want_next);			# Global variables for finite state machine.
our ($chado, %prepared_queries);	# Global variables for communication with Chado.

# A set of Peeves-global variables for communicating between different proformae.

our $g_FBrf;			# Publication ID: from P22 to (G31b, GA32b, A27b, AB11b)
our $g_pub_type;		# Publication type: from P1 to (*[12]b, GA10[a-h])
our $unattributed;              # Set to 1 if P22 = 'unattributed', otherwise '0'

# $g_num_syms is the number of symbols in a hash list in either G1a (gene.pl) or A1a (aberration.pl).
# $g_num_syms is used within gene.pl or aberration.pl when calling dehash in checking of fields
# within the gene or aberration proforma, hence these modules have no need for a file-global
# $hash_entries variable, as $g_num_syms is used.
# $g_num_syms is used in allele.pl and balancer.pl (hence it is a Peeves-global variable)
# to check that only one of the gene+allele or aberration+balancer pair contains hashing.
# This should be the only use of $g_num_syms in allele.pl or balancer.pl and these two modules
# use a file-global $hash_entries variable when calling dehash in checking of fields within
# the allele or balancer (variant) proforma. gm131210.
our $g_num_syms;

our $g_gene_sym_list;		# globally visible reference to list of gene symbols
our $g_gene_species_list;		# globally visible reference to list of species derived from gene symbols
our %x1a_symbols;		# For detecting duplicate proformae in a record

our $change_count = 0; # count of number of !c lines in the proforma, peeves global as needs to be seen by changes in tools.pl

my ($file, $proforma);
my $proforma_change;		# Whether a !c has been used anywhere in the proforma.
my %proforma_fields;		# Keep track of the latest entry seen for each code
my %dummy_dup_proforma_fields;	# dummy (as no fields can be duplicated in proforma) hash to keep check_dups happy
my @inclusion_essential = qw (G1a G1g);	# Fields which must be present in the proforma

# A set of file-global variables for communicating between different proforma fields.

my @FBgn_list = ();		# List of FBgn identifiers given in G1h

my @G28b_list = ();		# List of lists of lists of gene symbols given in G28b
my @G1e_list = ();		# Dehashed data from G1e
my @G1f_list = ();		# Dehashed data from G1f
my @G2c_list = ();		# Dehashed data from G2c.
my $G31b_yes = 0;		# y/n data gives a bad data error if hashes so one variable in G31b - moved to Peeves
my @G32_data = ();		# Dehashed data from G32
my %ic_go_ids = ();		# List of GO-ids seen in "inferred by curator" evidence codes
my %exp_go_ids = ();		# List of GO-ids seen preceding experimental evidence codes
my $exp_ev_codes = 'IDA, IEP, IPI, IGI or IMP';	# Current list of experimental evidence codes
my $go_provenance = 'FlyBase';	# GO provenance, default is FlyBase.
my $seen_G24 = 0;		# To ensure that G24f is present if any other G24 is.
my $firstGene; # record gene name early from G1a field because G1h comes before...

# gm - adding new variables for cross-checking of G35 and G26 fields
my ($G26_data, $G35_data);

sub do_gene_proforma ($$)
{
# Process a gene proforma, the text of which is in the second argument which has been read from
# the file named in the first argument.

    ($file, $proforma) = @_;			# Set global variables for convenience.

    %proforma_fields = ();
	%dummy_dup_proforma_fields = ();
# Get initial gene name, also in new records with G1h first... (new proforma line)
# The first occurring G1a record defines the number of expected symbols in a hash list.
	$firstGene = '';
	
    $proforma =~ /!.? G1a\..*? :(.*)/;		# Get G1a data, if any
    {
	no warnings;				# split in scalar context raises deprecation warning.
	$g_num_syms = split / \# /, $1;		# Count fields containing gene names
	$firstGene = $1;
    }
#	report($file, $g_num_syms." fields submitted and G1a is $1\n\n");
    
	$g_gene_sym_list = ['Missing_primary_symbol_data'];	# Set a default so that other checks don't fail with undef value and so that it is reset each time encounters a gene proforma.
	$g_gene_species_list = ['Missing_primary_symbol_data'];	# Set a default so that other checks don't fail with undef value and so that it is reset each time encounters a gene proforma.


	$change_count = 0;


    @FBgn_list = ();				# Flush any data remaining from a previous call
    @G28b_list = ();
    @G1e_list = ();
    @G1f_list = ();
	@G2c_list = ();
	$G31b_yes = 0;		# Peeves won't permit hash of y/n fields
    @G32_data = (); 
    %ic_go_ids = ();
    %exp_go_ids = ();
    $go_provenance = 'FlyBase';
    $seen_G24 = 0;

# A set of local variables for post-checks.

    my $G1g_data = '';			# The y/n data found in G1g
    my $G31b_data = '';			# The y/n data found in G31b


	my @G1g_list = (); # dehashed data from G1g field (may eventually replace $G1g_data, but not sure if that is possible/desirable yet

# the arrays below store data returned by process_field_data (or equivalent),
# so are dehashed, but have NOT been split on \n
	my @G1b_list = ();
	my @G2a_list = ();
	my @G2b_list = ();
	my @G30_list = ();
	my @G5_list = ();
	my @G6_list = ();
	my @G7a_list = ();
	my @G7b_list = ();
	my @G8_list = ();
	my @G91_list = ();
	my @G91a_list = ();

	my @G39a_list = ();
	my @G39b_list = ();
	my @G39c_list = ();
	my @G40_list = ();
	my @G38_list = ();


# gm - adding new variables for cross-checking of G35 and G26 fields
	($G26_data, $G35_data) = ('') x 2;

FIELD:
    foreach my $field (split (/\n!/, $proforma))
    {
	if ($field =~ /^(.*?) (G1h)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_G1h ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (G1a)\..*? :(.*)/s)
	{

	    my ($change, $code, $data) = ($1, $2, $3);

	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);


# If the primary proforma field does not pass the basic test that it
# is not empty AND contains a single line of data
# return and do not try to check the remaining fields.
# The $want_next variable is set to that expected next after this
# proforma type, to make sure that the next proforma will be checked
# (this is technically only required for those proformae that have
# child proformae nested under them e.g. gene->allele, aberration->balancer
# but put it in all primary profomra fields, in case the $want_next
# requirements for others change at a later date, to be safe).

		unless (contains_data ($file, $code, $data, $proforma_fields{$code}) && single_line ($file, $code, $data, $proforma_fields{$code})) {
			$want_next = $fsm{'GENE'};
			return;
		}

	    ($g_gene_sym_list, $g_gene_species_list) = validate_primary_proforma_field ($file, $code, $change, $g_num_syms, $data, \%proforma_fields);

	}
	elsif ($field =~ /^(.*?) (G1b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		@G1b_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (G1e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		unless (double_query ($file, $2, $3)) {
			@G1e_list = validate_rename ($file, $2, $g_num_syms, $1, $3, $proforma_fields{$2});
		}

	}
	elsif ($field =~ /^(.*?) (G1f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    check_non_utf8 ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		unless (double_query ($file, $2, $3)) {

			@G1f_list = validate_x1f ($file, $2, $g_num_syms, $1, $3, $proforma_fields{$2});
		}

	}
	elsif ($field =~ /^(.*?) (G1g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    $G1g_data = $3; # for now, keeping $G1g_data (not dehashed) as well as storing @G1g_list (dehashed), until worked out whether its safe/desirable to change existing code to use dehashed @G1g_list version [gm140625]
        
		unless (double_query ($file, $2, $3)) {
			@G1g_list = validate_x1g ($file, $2, $g_num_syms, $1, $3, $proforma_fields{$2});
		}
#	    double_query ($file, $2, $3) or validate_x1g ($file, $2, $1, $3, $proforma_fields{$2});

	}
	elsif ($field =~ /^(.*?) (G30)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		@G30_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (G2a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		@G2a_list = process_field_data ($file, $g_num_syms, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (G2b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		@G2b_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (G2c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		@G2c_list = process_field_data ($file, $g_num_syms, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (G27)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (G31a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    check_non_utf8 ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			validate_obsolete ($file, $1, $2, $3, \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?) (G31b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_G31b ($2, $1, $3);
# following almost works for replacing validate_G31b but need to sort out requirement
# for $G31b_yes in G1b/G2b cross-checks first
#	    double_query ($file, $2, $3) or validate_dissociate ($file, $1, $2, $3,  \%proforma_fields);
	}
	elsif ($field =~ /^(.*?) (G10[ab])\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_G10ab ($1, $2, $3, \%proforma_fields);

	}
	elsif ($field =~ /^(.*?) (G11)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_G11 ($2, $1, $3, \%proforma_fields);
	}
	elsif ($field =~ /^(.*?) (G14a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}

	elsif ($field =~ /^(.*?) (G28a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (G28b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_G28b ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (G24g)\..*?:(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		check_non_utf8 ($file, $2, $3);
		double_query ($file, $2, $3) or validate_G24g ($2, $1, $3);

		if (defined $3 && $3 ne '') {
			unless (valid_symbol ($file, 'curator_type') eq 'GOCUR') {
				report ($file, "%s: **WARNING**: GO fields should no longer be used as moving to Protein2GO\n!%s", $2, $proforma_fields{$2});

			}
		}
	}
	elsif ($field =~ /^(.*?) (G24a)\..*?:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_G24abc ($2, $1, $3);

		if (defined $3 && $3 ne '') {
			unless (valid_symbol ($file, 'curator_type') eq 'GOCUR') {
				report ($file, "%s: **WARNING**: GO fields should no longer be used as moving to Protein2GO\n!%s", $2, $proforma_fields{$2});

			}
		}

	}
	elsif ($field =~ /^(.*?) (G24b)\..*?:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_G24abc ($2, $1, $3);

		if (defined $3 && $3 ne '') {
			unless (valid_symbol ($file, 'curator_type') eq 'GOCUR') {
				report ($file, "%s: **WARNING**: GO fields should no longer be used as moving to Protein2GO\n!%s", $2, $proforma_fields{$2});

			}
		}

	}
	elsif ($field =~ /^(.*?) (G24c)\..*?:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_G24abc ($2, $1, $3);

		if (defined $3 && $3 ne '') {
			unless (valid_symbol ($file, 'curator_type') eq 'GOCUR') {
				report ($file, "%s: **WARNING**: GO fields should no longer be used as moving to Protein2GO\n!%s", $2, $proforma_fields{$2});

			}
		}

	}
	elsif ($field =~ /^(.*?) (G24e)\..*?:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');

		if (defined $3 && $3 ne '') {
			unless (valid_symbol ($file, 'curator_type') eq 'GOCUR') {
				report ($file, "%s: **WARNING**: GO fields should no longer be used as moving to Protein2GO\n!%s", $2, $proforma_fields{$2});

			}
		}

	}
	elsif ($field =~ /^(.*?) (G24f)\..*?:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_G24f ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (G15)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}

	elsif ($field =~ /^(.*?) (G5)\..*?:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		@G5_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (G6)\..*?:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		@G6_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (G7a)\..*?:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		@G7a_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (G7b)\..*?:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		@G7b_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (G8)\..*?:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    @G8_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (G26)\..*?:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
	    double_query ($file, $2, $3) or validate_G26 ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (G32)\..*?:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_G32 ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (G33)\..*?:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		check_site_specific_field($file, $2, 'Harvard', \%proforma_fields) if $3;
		process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (G34)\..*?:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (G35)\..*?:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_G35 ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (G37)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (G91)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		@G91_list = process_field_data ($file, $g_num_syms, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (G91a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		@G91a_list = process_field_data ($file, $g_num_syms, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(G39a)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		@G39a_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(G39b)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		@G39b_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(G39c)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		# got both a process_field_data check (empty in Peeves so just the basics)
		# and validate_G24f as hard to do both within and between field checks without
		# rewriting validate_G24f.
		@G39c_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');
		validate_G24f ($2, $1, $3);

	}
	elsif ($field =~ /^(.*?)\s+(G39d)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(G40)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		@G40_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(G38)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		@G38_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(G41)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $g_gene_sym_list, 0);
		process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}

	elsif ($field =~ /^(.*?) G(.+?)\..*?:(.*)$/s)
	{
	    report ($file, "Invalid proforma field\n!%s", $field);
	} elsif ($field =~ /.*G.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
		    report ($file, "Malformed proforma field (message tripped in gene.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n'!%s'", $field);
		}
	}
    }

### Start of tests that can only be done after parsing the entire proforma. ###

    $seen_G24 and push @inclusion_essential, 'G24f';
    check_presence ($file, \%proforma_fields, \@inclusion_essential, $g_gene_sym_list);
    $seen_G24 and pop @inclusion_essential;

	if ($g_num_syms and exists $proforma_fields{'G1h'}) # new from March 09 V.1.3.0 
    {	
		cross_check_FBid_symbol ($file, 1, 0, 'FBgn', 'gene', $g_num_syms,
				 'G1h', \@FBgn_list, 'G1a', $g_gene_sym_list,
				 'G1e', \@G1e_list,  'G1f', \@G1f_list);
    }
	
    if ($g_num_syms and exists $proforma_fields{'G1g'})
    {
	cross_check_1a_1g ($file, 'G', 'FBgn', 'gene', $g_num_syms, $G1g_data, $g_gene_sym_list);

    }


# If G1e is filled in, check G1g is 'n'
	if ($g_num_syms and exists $proforma_fields{'G1e'}) {

		cross_check_x1e_x1g ($file, 'G1e', $g_num_syms, $G1g_data, \@G1e_list, $proforma_fields{'G1e'});

	}

# G2c and G1f must not both be filled in
	compare_field_pairs ($file, $g_num_syms, 'G1f', \@G1f_list, 'G2c', \@G2c_list, \%proforma_fields, 'single', '');

# G2a must be filled in for a merge/rename (unless there is no name to give for the gene)
	compare_field_pairs ($file, $g_num_syms, 'G1f', \@G1f_list, 'G2a', \@G2a_list, \%proforma_fields, 'dependent::(i.e. gene merge)', '');



# If G2c is filled in, G2a must be filled in. PLUS value in G2a and G2c must not be the same
compare_field_pairs ($file, $g_num_syms, 'G2c', \@G2c_list, 'G2a', \@G2a_list, \%proforma_fields, 'dependent::(unless you are trying to delete the fullname in chado)', 'not same');

# check for fields that are limited to Dmel only
	filled_in_for_dmel_only ($file, $g_num_syms, $g_gene_species_list, 'G5', \@G5_list, \%proforma_fields);
	filled_in_for_dmel_only ($file, $g_num_syms, $g_gene_species_list, 'G6', \@G6_list, \%proforma_fields);

	filled_in_for_dmel_only ($file, $g_num_syms, $g_gene_species_list, 'G7a', \@G7a_list, \%proforma_fields);
	filled_in_for_dmel_only ($file, $g_num_syms, $g_gene_species_list, 'G7b', \@G7b_list, \%proforma_fields);
	filled_in_for_dmel_only ($file, $g_num_syms, $g_gene_species_list, 'G8', \@G8_list, \%proforma_fields);


## cross-checks based on 'status' of gene in proforma
	if ($g_num_syms) {

		for (my $i = 0; $i < $g_num_syms; $i++) {

# get the 'status' of the gene being checked
			my $object_status = get_object_status ('G', $G1g_list[$i], $G1e_list[$i], $G1f_list[$i]);

			if ($object_status) {

				if ($object_status eq 'existing') {

					if (defined $G2a_list[$i] && $G2a_list[$i] ne '') {

						report ($file, "%s: You have given data (%s) for an existing gene '%s'. Did you mean to put it in G2b?", 'G2a', $G2a_list[$i], $g_gene_sym_list->[$i]);

					}


				} elsif ($object_status eq 'rename') {

# G2a/G2c cross-checks - only do checks if symbol in G1e is in chado

						if (my $rename_id = valid_chado_symbol($G1e_list[$i], 'FBgn')) {

# reference to an array containing the valid name(s) in chado - should only ever be
# one valid name, but just in case
							my $chado_fullname_ref = chat_to_chado ('feature_fullname_from_id', $rename_id)->[0];
#							warn "$file: G1e: $G1e_list[$i], id: $rename_id, name: \n";
#							warn Dumper ($chado_fullname_ref);


# G2a filled in
							if (defined $G2a_list[$i] && $G2a_list[$i] ne '') {

								unless (defined $G2c_list[$i] && $G2c_list[$i] ne '') {

									if (defined $chado_fullname_ref) {

										report ($file, "G2c must be filled in for a rename where a fullname exists in chado. Did you mean to put '%s' (the valid fullname for '%s') in G2c ?\n!%s\n!%s\n!%s\n!%s", (utf2sgml(join (' ', @{$chado_fullname_ref}))), $G1e_list[$i],  $proforma_fields{'G1a'}, $proforma_fields{'G1e'},  $proforma_fields{'G2a'},  $proforma_fields{'G2c'});

									}

								}

# G2a not filled in
							} else {

# G2c not filled in
								unless (defined $G2c_list[$i] && $G2c_list[$i] ne '') {

									if (defined $chado_fullname_ref) {

										report ($file, "Neither G2a nor G2c are filled in, but G1e contains '%s' (this gene has a fullname in chado). This is only allowed if you are trying to rename a gene's symbol without changing the full name.\n!%s", $G1e_list[$i], $proforma_fields{'G1e'});

									} else {

										report ($file, "Neither G2a nor G2c are filled in, but G1e contains '%s' (this gene has no fullname in chado). If you want to name this gene, fill in G2a.\n%s", $G1e_list[$i], $proforma_fields{'G1e'});

									}
								}
							}
						}


# G28b cross-check
					unless (defined $G28b_list[$i] && $G28b_list[$i] ne '') {

						report ($file,"You have not filled in a 'Source for identity of: ' line in G28b for the following rename:\n!%s", $proforma_fields{'G1e'});
					} else {

						my (@G28b_genes) = @{$G28b_list[$i]};
						my $operation = shift @G28b_genes; # validate_G28b left 'identity' or 'merge' as the first array entry.

						unless ($operation eq 'identity') {

							report ($file,"Rename field (G1e) is filled in, but 'Source for %s of: %s' line in G28b contains '%s', did you mean 'identity' instead in G28b ?", $operation, join (' ', @G28b_genes), $operation);


						}
					}





				} elsif ($object_status eq 'merge') {

					unless (defined $G28b_list[$i]) {

						report ($file,"You have not filled in a 'Source for merge of: ' line in G28b for the following merge:\n!%s", $proforma_fields{'G1f'});
					} else {

						my (@G28b_genes) = @{$G28b_list[$i]};
						my $operation = shift @G28b_genes; # validate_G28b left 'identity' or 'merge' as the first array entry.

						unless ($operation eq 'merge') {

							report ($file,"Merge field (G1f) is filled in, but 'Source for %s of: %s' line in G28b contains '%s', did you mean 'merge' instead in G28b ?", $operation, join (' ', @G28b_genes), $operation);

						}
					}
				} elsif ($object_status eq 'new') {
				# a lot of the checks for new objects are done using check_filled_in_for_new_feature so this loop only contains those that need to be handled a bit differently
					if (scalar @{$g_gene_sym_list}>1 or scalar @{$g_gene_species_list}>1) {

						report ($file, "When gene symbol(s) in G1a contain hashing, Peeves can\'t manage G35 and G26 checking for new gene entries. Either submit the hashed proforma at your own risk ;), or separate out the genes into separate proformae for more complete peeves checking.");



					} else {

						my $gene_species = $g_gene_species_list->[0];

						unless (valid_symbol ($gene_species, "taxgroup:drosophilid")) {

							unless ($G26_data) {

								report ($file, "%s must be filled in for a new non-drosophilid gene.\n!%s\n", "G26", $proforma_fields{'G1a'});

							}

						}
					}
				}


			}
		}
	}

##


##

##

# G1e and G1f must not both contain data.

	rename_merge_check ($file, 'G1e', \@G1e_list, $proforma_fields{'G1e'}, 'G1f', \@G1f_list, $proforma_fields{'G1f'});

# check for rename across species.
	check_for_rename_across_species ($file, $g_num_syms, 'G', $g_gene_species_list, \@G1e_list, \%proforma_fields);

# no !c if G1f is filled in

	plingc_merge_check ($file, $change_count,'G1f', \@G1f_list, $proforma_fields{'G1f'});

# cross-checks for fullname renames
	cross_check_full_name_rename ($file, 'G', $g_num_syms, $g_gene_sym_list, \@G1e_list, \@G2c_list, \%proforma_fields);


# G28b checking.  G28b is not required to contain data but if it does it must be cross-checked with G1e and
# G1f.

    if ($g_num_syms and $#G28b_list + 1 == $g_num_syms) {
		for (my $i = 0; $i < $g_num_syms; $i++) {
	    	my (@G28b_genes) = @{$G28b_list[$i]};
			my $operation = shift @G28b_genes;			# validate_G28b left 'identity' or 'merge' at front.

# check for duplicated symbols in list of genes
			check_for_duplicated_lines($file, 'G28b', join ("\n", @G28b_genes), $proforma_fields{'G28b'});

			if ($operation eq 'identity') {

# G28b data must contain the data in G1a.  If there is a value in G1e, that value must also appear in G28b.
				if (defined $G1e_list[$i]) {

					my $missing_G1a = 1;
					foreach my $G28b_gene (@G28b_genes) {
						$missing_G1a &&= $G28b_gene ne $g_gene_sym_list->[$i];
					}
					$missing_G1a and report ($file, "G28b: G1a symbol '%s' does not occur in 'Source for identity of: %s", $g_gene_sym_list->[$i], join (' ', @G28b_genes));

					if ($#G1e_list + 1 == $g_num_syms) {
						my $missing_G1e = 1;
						foreach my $G28b_gene (@G28b_genes) {
							$missing_G1e &&= $G28b_gene ne $G1e_list[$i];
						}
						$missing_G1e and report ($file, "G28b: G1e symbol '%s' does not occur in 'Source for identity of: %s", $G1e_list[$i], join (' ', @G28b_genes));
					}
				} else {

					report ($file, "You have filled in 'Source for identity of: %s', but have not filled in the corresponding G1e field.", join (' ', @G28b_genes));
				}
			} else {
# Must be 'merge' because of validate_G28b().  Enforce identity of data with G1f, but allow that the symbols
# may not be in the same order.

				my @sorted_G28b_genes = sort @G28b_genes;

				if (defined $G1f_list[$i]) {
				    my @sorted_G1f_genes = sort @{$G1f_list[$i]};
		    		my $ok_so_far = ($#sorted_G28b_genes == $#sorted_G1f_genes);

					for (my $j = 0; $ok_so_far and $j <= $#sorted_G1f_genes; $j++) {
						$ok_so_far &&= $sorted_G28b_genes[$j] eq $sorted_G1f_genes[$j];
					}
					unless ($ok_so_far) {
						report ($file, "Mismatch between genes listed in G1f and in G28b:\n!%s\n!%s", $proforma_fields{'G1f'},$proforma_fields{'G28b'});
		    		}
				} else {
		    		report ($file, "You have filled in 'Source for merge of: %s', but have not filled in the corresponding G1f field.", join (' ', @G28b_genes));
				}
			}
		}
	}

    if ($g_num_syms and exists $proforma_fields{'G32'} and $#G32_data + 1 == $g_num_syms)
    {
	if (exists $proforma_fields{'G1f'})
	{
	    if ($#G1f_list + 1 == $g_num_syms)
	    {

# The fact that the data has been through dehash() ensures that the two arrays have the same number
# of elements, so compare them on an element by element basis.

		for (my $i = 0; $i < $g_num_syms; $i++)
		{
		    next if $G32_data[$i] eq '';	# Absence of data is ok.
		    foreach my $G1f_datum (@{$G1f_list[$i]})
		    {
			$G1f_datum eq $G32_data[$i] and report ($file, "G1f and G32 both contain '%s'.", $G1f_datum);
		    }
		}
	    }
	    else
	    {
# Nothing to do because dehash () will already have complained about the G1f data error.
	    }
	}
	else
	{
	    report ($file, "You filled in G32 but omitted G1f entirely!");
	}
    }





# Require that everything in the "inferred by curator" list appears at least once in the experimental evidence
# list.  This stuff comes from the G24[abc] fields.

    foreach my $code (keys %ic_go_ids)
    {
	foreach my $go_id (@{$ic_go_ids{$code}})
	{
	    unless (exists $exp_go_ids{$go_id})
	    {
		report ($file, "%s: Incorrect use of IC; '%s' must be assigned with experimental evidence (%s)",
			$code, $go_id, $exp_ev_codes);
	    }
	}
    }

	if (defined $g_gene_species_list) {
		crosscheck_G26_G35($G26_data,$G35_data);
	}
compare_field_pairs ($file, $g_num_syms, 'G6', \@G6_list, 'G5', \@G5_list, \%proforma_fields, 'dependent', '');

compare_field_pairs ($file, $g_num_syms, 'G91', \@G91_list, 'G91a', \@G91a_list, \%proforma_fields, 'pair::if either is filled in', '');

check_filled_in_for_new_feature ($file, 'G30', $g_num_syms, \@G30_list, \@G1g_list, \@G1e_list, \@G1f_list, \%proforma_fields, 'yes');

# check that new foreign gene information is attributed to the correct reference

	if ($G26_data) {
		$g_FBrf eq 'FBrf0199194' and return;
		report ($file, "%s data must be attributed to the FBrf0199194 reference but P22 specifies '%s'.", 'G26', $g_FBrf ? $g_FBrf : ($unattributed ? 'unattributed' : 'new'));

	}

	if ($G35_data) {
		$g_FBrf eq 'FBrf0199194' and return;
		report ($file, "%s data must be attributed to the FBrf0199194 reference but P22 specifies '%s'.", 'G35', $g_FBrf ? $g_FBrf : ($unattributed ? 'unattributed' : 'new'));

	}

# gene summary field checks

for (my $i = 0; $i < $g_num_syms; $i++) {

	if ($G39a_list[$i] && $G39a_list[$i] ne '') {

		unless ($G39b_list[$i] eq 'y') {
			report ($file, "G39b must be filled in with 'y' when G39a is filled in:\n!%s\n!%s", $proforma_fields{'G39a'}, $proforma_fields{'G39b'});

		}
	}

	if ($G39b_list[$i] && $G39b_list[$i] eq 'n') {
		unless ($G39c_list[$i] && $G39c_list[$i] ne '') {

			report ($file, "G39c must be filled in when G39b contains 'n':\n!%s\n!%s", $proforma_fields{'G39b'}, $proforma_fields{'G39c'});

		}
	}



# check that the gene filled in in G38 is a 'generic gene'

	if (defined $G38_list[$i] && $G38_list[$i] ne '') {

		my $switch = 0;
		if (my $id = valid_chado_symbol($G38_list[$i], 'FBgn')) {

			my $chado_ref = chat_to_chado ('SO_annotation', $id);
			foreach my $element (@{$chado_ref}) {

				my ($SO_term) = @{$element};

				if (valid_symbol ($SO_term, 'G38_SO_types')) {
					$switch++;
					last;
				} 

			}

			unless ($switch) {

				report ($file, "%s: The '%s' gene does not have one of the allowed SO terms for a 'generic gene' attached to it in chado: check whether you picked the right gene, or whether you need to add a 'generic gene' SO term to %s using the appropriate FlyBase analysis reference, before loading this record.", 'G38', $G38_list[$i], $G38_list[$i]);
			}
		}

	}


}

# G39c must be filled in if G39a is filled in
compare_field_pairs ($file, $g_num_syms, 'G39a', \@G39a_list, 'G39c', \@G39c_list, \%proforma_fields, 'dependent', '');


# check that valid symbol is in the symbol synonym field when !c-ing it under the  'unattributed' pub.
# Only do the check if the symbol synonym field contains some data
if ($unattributed && $#G1b_list + 1 == $g_num_syms) {

	check_unattributed_synonym_correction ($file, $g_num_syms, 'G1a', $g_gene_sym_list, 'G1b', \@G1b_list, \%proforma_fields, "You must include the valid symbol in G1b when \!c-ing it under the 'unnattributed' publication.");

}


### End of tests that can only be done after parsing the entire proforma. ###

# The following line must always be at the bottom of this subroutine

    $want_next = $fsm{'GENE'};	# Specify what we're prepared to deal with next.
}

sub validate_G1h ($$$)#new from March 09 ie test >> production
{
# Data is either a single FBgn or empty.  It must be present for author-curated proformae.  Issue a warning if
# it is present in other proforma types.

    my ($code, $change, $FBgns) = @_;
    $FBgns = trim_space_from_ends ($file, $code, $FBgns);

    if (valid_symbol ($file, 'curator_type') eq 'USER' || valid_symbol ($file, 'curator_type') eq 'AUTO')
    {
	$FBgns eq '' and report ($file, "%s: %s-curated proformae must have data.", $code, valid_symbol ($file, 'curator_type'));
    }
    else
    {
	$FBgns eq '' or report ($file, "%s: Curators don't usually fill in the FBgn field.  " .
				"Are you sure you want to for '%s'?", $code, $firstGene, join (' # ', @{$g_gene_sym_list}));
    }
    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$proforma_fields{$code});

	single_line ($file, $code, $FBgns, $proforma_fields{$code}) or return;

    @FBgn_list = FBid_list_check ($file, $code, 'FBgn', $g_num_syms, $FBgns);

# More tests at the post-check phase.
}



sub validate_G31b ($$$) # y then only G1a must be filled in and nothing else
{
    my ($code, $change, $delete) = @_;
    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$proforma_fields{$code});
    $delete = trim_space_from_ends ($file, $code, $delete);
    return if $delete eq '';
    
    # No need to dehash here since it only depends on ONE reference
	 my $plural = "";
	 if(scalar @{$g_gene_sym_list}>1){$plural ="s";}
		if ($delete eq 'y')		# Yea from the table of my memory I'll wipe away all trivial fond records.
		{	
			$G31b_yes=1; # New int to stop 'G1b and G2b do not contain data' messages Now set in Peeves for comms between proformae and elimination of false P41 Missing data...
			if (valid_symbol ($g_FBrf, 'FBrf')) # reference valid
			{
				report ($file, "%s: Do you *really* want to dissociate gene symbol$plural '%s' from %s?",
					$code, join (" \# ", @{$g_gene_sym_list}), $g_FBrf);
			}
			else
			{
				report ($file, "%s: The FBrf from P22 ('%s') is not a valid publication from which to dissociate '%s'",
					$code, $g_FBrf, join (" \# ", @{$g_gene_sym_list}));
			}
			# Check all other conditions during the post-check phase.
		}
		else
		{
				report ($file, "%s: '%s' not allowed.", $code, $delete);
		}
}

sub validate_G10ab {
# not converted to process_field_data + %field_specific_checks format as need to check species of entry
# in G1a field before deciding how to check data, so need to do dehash within validate_G10ab
    my ($change, $code, $data, $context) = @_;

    changes ($file, $code, $change);		# Check for garbage, but otherwise don't worry about $change.

    $data eq '' and return;		# Absence of data is always acceptable.

    my @dehashed_data = dehash ($file, $code, $g_num_syms, $data);

	if (@dehashed_data) {
		for (my $i = 0; $i < $g_num_syms; $i++) {

			my $uniqued_data = check_for_duplicated_lines($file,$code,$dehashed_data[$i],$context->{$code});

			# Only know how to check Dmel cyto positions.
			if ($g_gene_species_list->[$i] eq 'Dmel') {

				foreach my $datum (keys %{$uniqued_data}) {
					validate_cytological_location ($file, $code, $datum, $context);
				}

			} else {
					report ($file, "%s: Must not be filled in for the non-Dmel species '%s' \n!%s\n!%s", $code, $g_gene_species_list->[$i], $context->{G1a}, $context->{$code});

			}
		}
	}
}


sub validate_G11 ($$$) {
	my ($code, $change, $cyto_comments, $context) = @_;
	changes ($file, $code, $change);		# Check for garbage, but otherwise don't worry about $change.
	$cyto_comments eq '' and return;		# Absence of data is always acceptable.

	my @comments = dehash ($file, $code, $g_num_syms, $cyto_comments);

	if (@comments) {
		for (my $i = 0; $i < $g_num_syms; $i++) {
			my $comment = trim_space_from_ends ($file, $code, $comments[$i]);
			next if $comment eq '';			# Absence of data is always acceptable.

			if ($g_gene_species_list->[$i] eq 'Dmel') {
				if (my ($loc, $allele) = ($comment =~ /^Location(.*?) inferred from insertion in:(.*)/s)) {
					if ($loc ne '') {
						if (my ($location) = ($loc =~ /^ (\S+)$/)) {

							foreach my $invalid (cyto_check ($location)) {
								report ($file, "%s: Invalid cytological map position '%s' in '%s'", $code, $invalid, $location);
							}
						} else {
							report ($file, "%s: Invalid cytological map position '%s'", $code, $loc);
						}
					}
					if ($allele =~ /^ (\S+)$/) {
						valid_symbol ($1, 'FBal') or report ($file, "%s: Invalid allele symbol '%s'", $code, $1);
					} else {
						report ($file, "%s: Invalid allele symbol '%s'", $code, $allele);
					}
				} else {
					check_stamps ($file, $code, $cyto_comments);
				}

			} else {

				report ($file, "%s: Must not be filled in for the non-Dmel species '%s' \n!%s\n!%s", $code, $g_gene_species_list->[$i], $context->{G1a}, $context->{$code});
			}
		}
	}
}



sub validate_G28b ($$$)
{
    my ($code, $change, $gene_list) = @_;
    changes ($file, $code, $change);		# Check for garbage, but otherwise don't worry about $change.
    @G28b_list = ();
    $gene_list eq '' and return;		# Absence of data is always acceptable.

    if ($gene_list =~ /\@/)			# No stamps allowed.
    {
	report ($file, "%s: It looks like you are wrongly trying to use a stamp in '%s'", $code, $gene_list, " No other checks to G28b until fixed.");
	return;					# Not much point trying to continue.
    }

    foreach my $gene_statement_list (dehash ($file, $code, $g_num_syms, $gene_list))
    {
		my @g_list = ();

		if (trim_space_from_ends ($file, $code, $gene_statement_list) =~ /\n/s) {
#		if ($gene_statement_list =~ /\n/s) {

			report ($file,"%s field contains multiple entries - are you sure that you meant to include all the following statements ?\n(NOTE: symbol validity checks have not been carried out on these multiple G28b lines)\n!%s\n!%s",$code,$proforma_fields{'G1a'},$proforma_fields{$code});
		}

		foreach my $gene_statement (split (/\n/, $gene_statement_list))
		{
			$gene_statement = trim_space_from_ends ($file, $code, $gene_statement);
	
			if ($gene_statement eq '')
			{
			# Nothing to do.
			}
			elsif ($gene_statement =~ /^Source for (identity|merge) of:( ?)(.+)/)
			{	
			$2 eq ' ' or report ($file, "%s: I think you omitted the space after the SoftCV prefix in '%s'",
						 $code, $gene_list);
	
	# There must be at least two gene symbols in there.
	
			my @sym_list = split (/ /, $3);

			$#sym_list or report ($file, "%s: You need more than just one symbol '%s'", $code, $sym_list[0]);


			if ($1 eq 'identity') {
				unless ($#sym_list ==1) {
					report ($file, "%s: Must have exactly two symbols in the '%s' line.",$code,$gene_statement);
				}
			}

			push @g_list, [($1, @sym_list)];	# Preserve gene_statement and list of genes
			}
			else
			{
			report ($file, "%s: Invalid SoftCV prefix '%s'", $code, $gene_statement);
			}

	# Further validation has to be done at the post-check phase.
		}
		push @G28b_list, @g_list;		# A list of lists...
    }
}




sub validate_G24g ($$$)
{
# GO --- date GO annotation set last reviewed.  

   my ($code, $change, $date_list) = @_;
   changes ($file, $code, $change) and report ($file, "%s: Can't use !c in the %s field (its in the %s proforma)", $code, $code, join (" \# ", @{$g_gene_sym_list}));

   $date_list eq '' and return;		# Absence of data is always acceptable.

# print warning as only GO curator should be filling this in.

   report ($file, "%s: Do you *really* want to fill in the %s field in %s? (should only be filled in by a GO curator)", $code, $code, join (" \# ", @{$g_gene_sym_list}));

    foreach my $date (dehash ($file, $code, $g_num_syms, $date_list))
	{

	$date = trim_space_from_ends ($file, $code, $date);
	if ($date =~ /\n/)
	{
	    report ($file, "%s: More than one date symbol in '%s'\n", $code, $date);
	    return;				# Not much point checking anything else.
	}

	
	bad_iso_date ($file, $code, $date);	# bad_iso_date() issues all necessary reports.	



	}

}

# Lookup tables of namespaces corresponding to each of the G24[abc] proformae field data and vice versa.

my %go_namespace = ('G24a' => 'cellular_component',
		    'G24b' => 'molecular_function',
		    'G24c' => 'biological_process');


sub validate_G24abc {

    my ($code, $change, $data_list) = @_;
    changes ($file, $code, $change);		# Check for garbage, but otherwise don't worry about $change.
    $data_list = trim_space_from_ends ($file, $code, $data_list);
    $data_list eq '' and return;		# Absence of data is always acceptable.

    $seen_G24 = 1;				# Seen a G24 field and it has data.


	my %root_term_mapping = (

		'G24a' => 'is_active_in',
		'G24b' => 'enables',
		'G24c' => 'involved_in',

	);

    foreach my $data (dehash ($file, $code, $g_num_syms, $data_list))
    {
	next if $data eq '';
	foreach my $datum (split ('\n', $data))
	{
	    $datum = trim_space_from_ends ($file, $code, $datum);
	    next if $datum eq '';

		my $term = '';
		my $qualifier = '';

# Assign provenance, and remove it from $datum for checking that follows
		($datum,$go_provenance) = set_provenance ($datum,$go_provenance,"GO");

# A single datum looks like <qualifier><GO_term> ; <GO_ID_number> | <evidence_code><evidence_data>
#
# First enforce basic structural similarity to this pattern and then slice up the datum

	    unless ($datum =~ / ; /)
	    {
		report ($file, "%s: Missing ' ; ' separator in '%s'", $code, $datum);
		next;
	    }
	    unless ($datum =~ / \| /)
	    {
		report ($file, "%s: Missing ' | ' separator in '%s'", $code, $datum);
		next;
	    }
	    unless ($datum =~ / ; .* \| /)
	    {
		report ($file, "%s: ' ; ' and ' | ' separators in wrong order in '%s'", $code, $datum);
		next;
	    }
	    my (undef, $qualified_term, $id, $evidence) = ($datum =~ /(NOT )?(.*?) ; (.*?) \| (.*)/);

# Check for a qualifier and remove it from the qualified_term if a valid one is found to allow subsequent checking of term

	    ($qualifier,$term) = check_qualifier($file, $code, $datum, $qualified_term);


# Back in the late Pleistocene we used to require EC data immediately after the GO_ID number.  There shouldn't
# be any of these fossils left lying around but check, just in case, and then remove them so that validation
# may continue.
	    if ($id =~ /(.*?) ; (EC.*)/)
	    {
		report ($file, "%s: Unwanted EC data ' ; %s' in '%s'", $code, $2, $id);
		$id = $1;
	    }

# Check $term and $id for validity

		check_ontology_term_id_pair ($file, $code, $term, $id, "GO:$go_namespace{$code}", $datum, '');

# Now the evidence data ...

	    do_go_evidence ($code, $datum, $id, $evidence);

# check format of root term annotations - exploit the fact that root terms have the same name as their namespace

		if ($term eq $go_namespace{$code}) {

# check evidence is ND
			unless ($evidence eq 'ND') {

				report ($file, "%s: '%s' in '%s' is not valid (only the 'ND' evidence code is allowed with the root term).",$code,$evidence, $datum);

			}


			unless ($qualifier eq $root_term_mapping{$code}) {

				report ($file, "%s: '%s' in '%s' is not valid (only the '%s' qualifier is allowed with the root term).",$code,$qualifier, $datum, $root_term_mapping{$code});


			}

			if ($datum =~ /^NOT/) {
				report ($file, "%s: the root term '%s' can not be used with 'NOT' in '%s'.",$code,$term, $datum);


			}
		}
	}
    }
}


sub do_go_evidence ($$$$)
{
# Validate GO evidence given in the fourth argument for the GO-id given in the third.  The first two argument
# tells us which proforma field is being validated and its data.

    my ($code, $context, $go_id, $evidence) = @_;
    my ($ev_code, $ev_data);

# The evidence consists of an evidence code possible followed by some evidence data.  Determining which is
# which can be a real bugger because the code can contain spaces and the word "from" which is also used as an
# introducer for the data portion in some circumstances.  This may help explain why the material below looks
# so ugly and why we can't just use a clever regexp and a call to valid_symbol().

    $evidence = trim_space_from_ends ($file, $code, $evidence);

# Have grouped evidence codes below into groups which have similar checking
# to make it easier to add new evidence codes/change requirements for existing evidence codes

# MANDATORIALLY HAS VALUE AFTER CODE: ' from ' followed by at least one GO:ID in format
# special case - IC
    if ((undef, $ev_data) = ($evidence =~ /^(inferred by curator|IC)(.*)/))
    {
       if (my ($ev_data) = ($ev_data =~ /^ from (.+)/))
       {
	   if ($ev_data =~ /\s/)
	   {
	       report ($file, "%s: Removing whitespace in '%s' from '%s' and checking what is left", $code, $ev_data, $context);
	       $ev_data =~ s/\s//g;
	   }
	   foreach my $go_id (split ('\|', $ev_data))
	   {
	       if (valid_symbol ($go_id, 'GO:default:id'))
	       {	# Stash away GO:ID's for checking against experimental evidence codes in the post-check phase.
		   if (exists $ic_go_ids{$code})
		   {
		       push @{$ic_go_ids{$code}}, $go_id;
		   }
		   else
		   {
		       $ic_go_ids{$code} = [$go_id];
		   }
	       }
	       else
	       {
		   report ($file, "%s: Invalid GO-id %s in '%s'", $code, $go_id, $context);
	       }
	   }
       }
       else
       {
	   report ($file, "%s: the evidence '%s' in '%s' does not look like ' from GO:1234567(|GO:7654321)...'", $code, $ev_data, $context);
       }
    }

# MANDATORIALLY HAS VALUE AFTER CODE: ' with ' followed by at least one database identifier
# i.e. must HAVE 'with ' after evidence code
# no other special requirements
    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from sequence alignment|ISA)(.*)/))
    {
		check_evidence_data ($file, $code, $context, $ev_code, $ev_data);
    }
    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from sequence orthology|ISO)(.*)/))
    {
		check_evidence_data ($file, $code, $context, $ev_code, $ev_data);
    }

# MANDATORIALLY HAS VALUE AFTER CODE: ' with ' followed by at least one database identifier
# i.e. must HAVE 'with ' after evidence code
# experimental evidence code, so value stored for checking against "inferred by curator" later.

    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from physical interaction|IPI)(.*)/))
    {
		$exp_go_ids{$go_id} = 1;	# Stash away for checking against "inferred by curator" later.

		check_evidence_data ($file, $code, $context, $ev_code, $ev_data);

    }
    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from genetic interaction|IGI)(.*)/))
    {
		$exp_go_ids{$go_id} = 1;	# Stash away for checking against "inferred by curator" later.

		check_evidence_data ($file, $code, $context, $ev_code, $ev_data);
    }

# MANDATORIALLY HAS VALUE AFTER CODE: ' with ' followed by at least one database identifier
# i.e. must HAVE 'with ' after evidence code
# should not be used in regular literature curation so requires extra warning

    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from biological ancestor|IBA)(.*)/))
    {

# warning only issued to non-GO curators
		unless (valid_symbol ($file, 'curator_type') eq 'GOCUR') {
			report ($file, "%s: The '%s' evidence code should not be used in regular literature curation, did you put the wrong evidence in '%s' ?",$code, $ev_code, $context);
		}

		check_evidence_data ($file, $code, $context, $ev_code, $ev_data);
    }
    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from biological descendant|IBD)(.*)/))
    {

# warning only issued to non-GO curators
		unless (valid_symbol ($file, 'curator_type') eq 'GOCUR') {
			report ($file, "%s: The '%s' evidence code should not be used in regular literature curation, did you put the wrong evidence in '%s' ?",$code, $ev_code, $context);
		}

		check_evidence_data ($file, $code, $context, $ev_code, $ev_data);
    }

    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from electronic annotation|IEA)(.*)/))
    {

# warning issued to all curators
		report ($file, "%s: The '%s' evidence code should not be used in manual literature curation, did you put the wrong evidence in '%s' ?",$code, $ev_code, $context);
		
		check_evidence_data ($file, $code, $context, $ev_code, $ev_data);
    }

# MANDATORIALLY HAS VALUE AFTER CODE: ' with ' followed by at least one database identifier
# i.e. must HAVE 'with ' after evidence code
# technically GO allows exceptions without 'with' for ISS, but as it is an exception to
# the normal rule, Peeves is set to make with mandatory for ISS.

    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from sequence or structural similarity|ISS)(.*)/))
    {
		check_evidence_data ($file, $code, $context, $ev_code, $ev_data);

    }

# MANDATORIALLY HAS VALUE AFTER CODE: ' with ' followed by at least one database identifier
# i.e. must HAVE 'with ' after evidence code
# should not be used in regular literature curation so requires extra warning
# MANDATORIALLY HAS NOT QUALIFIER BEFORE GO TERM

    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from rapid divergence|IRD)(.*)/))
    {

		unless (valid_symbol ($file, 'curator_type') eq 'GOCUR') {
			report ($file, "%s: The '%s' evidence code should not be used in regular literature curation, did you put the wrong evidence in '%s' ?",$code, $ev_code, $context);
		}

		$context !~/^NOT / and report ($file, "%s: '%s' evidence code must be used with NOT - either add NOT or change evidence code in '%s'",$code, $ev_code, $context);

		check_evidence_data ($file, $code, $context, $ev_code, $ev_data);

    }



# MANDATORIALLY HAS VALUE AFTER CODE:no value
# (i.e. must NOT have 'with ' or 'from ' after evidence code)
# no other special requirements
    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from reviewed computational analysis|RCA)(.*)/))
    {
		check_evidence_data ($file, $code, $context, $ev_code, $ev_data);
    }
    elsif (($ev_code, $ev_data) = ($evidence =~ /^(non-traceable author statement|NAS)(.*)/))
    {
		check_evidence_data ($file, $code, $context, $ev_code, $ev_data);
    }
    elsif (($ev_code, $ev_data) = ($evidence =~ /^(traceable author statement|TAS)(.*)/))
    {
		check_evidence_data ($file, $code, $context, $ev_code, $ev_data);
    }

# MANDATORIALLY HAS VALUE AFTER CODE:no value
# (i.e. must NOT have 'with ' or 'from ' after evidence code)
# experimental evidence code, so value stored for checking against "inferred by curator" later.

    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from mutant phenotype|IMP)(.*)/))
    {
		$exp_go_ids{$go_id} = 1;	# Stash away for checking against "inferred by curator" later.
		check_evidence_data ($file, $code, $context, $ev_code, $ev_data);
    }
    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from direct assay|IDA)(.*)/))
    {
		$exp_go_ids{$go_id} = 1;	# Stash away for checking against "inferred by curator" later.
		check_evidence_data ($file, $code, $context, $ev_code, $ev_data);
    }
    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from expression pattern|IEP)(.*)/))
    {
		$exp_go_ids{$go_id} = 1;	# Stash away for checking against "inferred by curator" later.
		check_evidence_data ($file, $code, $context, $ev_code, $ev_data);
	
	if ($code eq 'G24a') {

		report ($file, "%s: Invalid use of IEP evidence code in '%s'\nIEP can only be used with biological process terms. If the location of a gene product has been determined you should use IDA.",$code,$context);

	} elsif ($code eq 'G24b') {

		report ($file, "%s: Invalid use of IEP evidence code in '%s'\nInvalid use of IEP evidence code - IEP can only be used with biological process terms. Molecular function cannot be inferred directly from where a gene product is expressed.",$code,$context);

	}

    }

# MANDATORIALLY HAS VALUE AFTER CODE:no value
# (i.e. must not have 'with ' or 'from ' after evidence code)
# other special requirements

    elsif (($ev_code, $ev_data) = ($evidence =~ /^(no biological data available|ND)(.*)/))
    {
		check_evidence_data ($file, $code, $context, $ev_code, $ev_data);

	$g_FBrf eq 'FBrf0159398' and return;
	report ($file, "%s: Incorrect use of '%s' in '%s'\n" . "'%s' must only be assigned from the internal GO reference FBrf0159398 but P22 specifies %s", $code, $ev_code, $context, $ev_code, $g_FBrf ? $g_FBrf : 'no FBrf');
    }

    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from experiment|EXP)(.*)/))
    {
	$go_provenance eq 'FlyBase' and
	    report ($file, "%s: Incorrect use of EXP in '%s';\n" . "add provenance flag or use an alternative experimental evidence code.", $code, $context);

		check_evidence_data ($file, $code, $context, $ev_code, $ev_data);
    }

# OPTIONALLY HAS VALUE AFTER CODE (i.e. may have 'with ', followed by at least one database identifier after evidence code)

    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from genomic context|IGC)(.*)/))
    {

	check_evidence_data ($file, $code, $context, $ev_code, $ev_data);
    }
    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from sequence model|ISM)(.*)/))
    {

	check_evidence_data ($file, $code, $context, $ev_code, $ev_data);
    }


# OPTIONALLY HAS VALUE AFTER CODE (i.e. may have 'with ', followed by at least one database identifier after evidence code)
# MANDATORIALLY HAS NOT QUALIFIER BEFORE GO TERM

    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from key residues|IKR)(.*)/))
    {

	$context !~/^NOT / and report ($file, "%s: '%s' evidence code must be used with NOT - either add NOT or change evidence code in '%s'",$code, $ev_code, $context); # to catch this error, this must be done before checking whether there is 'with ' info in $ev_data below

	check_evidence_data ($file, $code, $context, $ev_code, $ev_data);
    }

    else
    {
	report ($file, "%s: Bad evidence code '%s' in '%s'", $code, $evidence, $context);
    }
}

sub validate_G24f ($$$)
{
# GO --- date terms in current proforma entered or last reviewed.  
# 'y' means insert date of loading; 'n' means preserve date already
# stored.

   my ($code, $change, $date) = @_;
   changes ($file, $code, $change);		# Check for garbage, but otherwise don't worry about $change.

	my %mapping = (

		'G24f' => 'GO',
		'G39c' => 'gene summary',

	);
   $date = trim_space_from_ends ($file, $code, $date);

   return if $date eq 'n' or $date eq 'y';

	single_line ($file, $code, $date, $proforma_fields{$code}) or return;


   if ($date eq '')
   {
       report ($file, "%s: Default value of 'y' removed from %s date field!  " .
	       "Any %s data will be recorded with new date. ", $code, $mapping{$code}, $mapping{$code});
   }

   else
   {
		unless (valid_symbol ($file, 'curator_type') eq 'GOCUR') {
			report ($file, "%s: WARNING: Non-%s curators don't usually put anything other than 'y' or 'n' in this field, did you mean to put '%s' ? ",$code, $mapping{$code}, $date);
		}
       bad_iso_date ($file, $code, $date);	# bad_iso_date() issues all necessary reports.	
   }
}

sub validate_G26 ($$$)
{
    my ($code, $change, $summaries) = @_;
    changes ($file, $code, $change);		# Check for garbage, but otherwise don't worry about $change.

    return if $summaries eq '';			# Absence of data is always permissible.

	$G26_data = $summaries; # store raw G26 data for cross-checking with other fields

    foreach my $summary (dehash ($file, $code, $g_num_syms, $summaries))
    {
	$summary = trim_space_from_ends ($file, $code, $summary);

	next if $summary eq '';				# Absence of data is always permissible.
	if ($summary =~ /\n/s)
	{
	    report ($file, "%s: Can't have multiple data '%s'", $code, $summary);
	    next;
	}

	if ($summary =~ /([^=])=([^=])/)
	{
	    report ($file, "%s: Single = in '%s'.  I'm carrying on, with the assumption that you meant ==.",
		    $code, $summary);
	    $summary =~ s/([^=])=([^=])/$1==$2/g;
	}

	if (my ($species, $gene, $accession_no) = ($summary =~ /^Foreign\ sequence;\ species\ ==\ (.+?);
						                  \ (gene|epitope\ tag|function\ tag|sequence\ tag)
						                  \ ==\ (.+?)(;\ .+?)?\.$/x))
	{
	    
	    unless ($species eq (valid_symbol ($g_gene_species_list->[0], 'chado_species_abbreviation'))) {
	    
	    	report ($file, "%s: species name '%s' in '%s' does not match the species abbreviation '%s' given in the gene symbol in G1a", $code, $species, $summary, $g_gene_species_list->[0]);
	    }

	}
	else
	{
	    report ($file, "%s: Invalid data in '%s'", $code, $summary);

# That could have been handled better, but this is a rarely used field and let's wait for curators to complain
# before investing a lot of effort.

	}
    }
}

sub validate_G32 ($$$)
{
    my ($code, $change, $ann_ids) = @_;
    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$proforma_fields{$code});
    @G32_data = dehash ($file, $code, $g_num_syms, $ann_ids);		# Save for post-check phase.

    return if $ann_ids eq '';				       		# Absence of data is always permissible.

    foreach my $ann_id (@G32_data)
    {
	$ann_id = trim_space_from_ends ($file, $code, $ann_id);

	next if $ann_id eq '';						# Absence of data is always permissible.
	if ($ann_id =~ /\n/s)
	{
	    report ($file, "%s: Can't have multiple data '%s'", $code, $ann_id);
	    next;
	}
	$ann_id =~ /^C(G|R)[0-9]{5}$/ or report ($file, "%s: Invalid annotation id '%s'.", $code, $ann_id);
    }
}


sub validate_G35 ($$$)
{


    my ($code, $change, $database_ids) = @_;
    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$proforma_fields{$code});

    return if $database_ids eq '';			# Do not go through the checks if the field is empty

	$G35_data = $database_ids; # store raw G35 data for cross-checking with other fields

	foreach my $database_id (split /\n/, $database_ids) {

		$database_id = trim_space_from_ends ($file, $code, $database_id);

		if ($database_id =~ m/^(.*?):(.*)/) {
			my ($database, $accession) = ($1, $2);

			if (defined $database && $database ne '') {

				valid_symbol ($database, 'chado database name') or report ($file, "%s: '%s' in '%s' is not a valid chado database name\n", $code, $database, $database_id);

			} else {
				report ($file, "%s: Missing database abbreviation in '%s'\n", $code, $database_id);

			}

			if ($accession =~m/\s/) {
				report ($file, "%s: Spaces not allowed in the '%s' accession portion of '%s'", $code, $accession, $database_id);

			}


		} else {

			report ($file, "%s: Unrecognized format '%s'", $code, $database_id);

		}


	}



}

sub crosscheck_G26_G35 ($$) {

	my ($G26_data,$G35_data) = @_;


	if (scalar @{$g_gene_sym_list}>1 or scalar @{$g_gene_species_list}>1) {

# only print error message when one of the fields contains data
		if ($G26_data or $G35_data) {

			report ($file, "When gene symbol(s) in G1a contain hashing, Peeves can\'t manage cross-checks between G35 and G26, or check that the database abbreviation given in G35 matches the species of the gene in G1a. Either submit the hashed proforma at your own risk ;), or separate out the genes into separate proformae for more complete peeves checking.");

		}

	} else {

		my ($G26_species, $G26_gene, $G26_accession_no) = ('') x '3';

# Only process G26 lines that are of the correct format and contain an accession number here.
# Other warnings do not need to be issued here as they are done in validate_G26
		if ($G26_data =~ m/^Foreign sequence; species \=\= (.+?); (gene|epitope tag|function tag|sequence tag) \=\= (.+?); (.+)\.$/) {
			($G26_species, $G26_gene, $G26_accession_no) = ($1, $2, $4);
		}

		my $found_accession = 0;
		foreach my $database_id (split /\n/, $G35_data) {

# The only check done here is for lines that have a valid database abbreviation
# Other warnings do not need to be issued here as they are done in validate_G35
			if ($database_id =~ m/^(.*?):(.*)/) {
				my ($database, $accession) = ($1, $2);

				my $gene = $g_gene_sym_list->[0];
				my $gene_species = $g_gene_species_list->[0];
				my $official_db = valid_symbol ($gene_species, 'official_db');
				if ($official_db) {

					unless ($database eq $official_db) {

						report ($file, "G35: The expected database for species '%s' of gene symbol '%s' is '%s', but the accession '%s' in G35 has '%s'.", $gene_species, $gene, $official_db, $database_id, $database);


					}

				} else {

					unless ($database eq 'GB' || $database eq 'UniProtKB') {

						report ($file, "G35: The database for the accession for a species without an 'official database' (SP6) is typically 'GB' or 'UniProtKB', but you have '%s' in '%s' - was this deliberate ?", $database, $database_id);

					}
				}


				if ($database_id eq $G26_accession_no) {
					$found_accession++;

				} else {

					if ($G26_data) {
						report ($file, "Mismatch between accession number '%s' given in G35 and accession portion '%s' given in G26.", $database_id, $G26_accession_no);
					} else {

						report ($file, "G35 contains accession number '%s' but G26 is not filled in.", $database_id);

					}

				}
			}
		}

		if ($G26_accession_no) {

			# add this to prevent 2 error messages for case where both G26 and G35 are filled in but accessions do not match.
			unless ($G35_data) {
				unless ($found_accession) {

					report ($file, "G26 contains the accession %s, but it is missing from the G35 field.", $G26_accession_no);
				}
			}
		}
	}
}



1;				# Standard boilerplate.
