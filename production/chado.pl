# Chado chado-related subroutines.

use strict;

our%Peeves_config;		# Global configuration variables.
our %prepared_queries;		# Pre-prepared queries of all types.
our $chado;			# Other routines need to be able to access Chado.

sub init_chado ()		# Set up a connection to the current production instance of Chado.
{

# First find out which Chado instance to use.  This information is itself held in a database which is kept up
# to date by the epicycle loading process.

#    my $db =  DBI->connect ("dbi:Pg:dbname=$Peeves_config{'Chado_db'};" .
#			    "host=$Peeves_config{'Chado_host'};" .
#			    "port=$Peeves_config{'Chado_port'}",
#			    $Peeves_config{'Chado_user'},
#			    $Peeves_config{'Chado_pass'},
#			    { RaiseError => 1, AutoCommit => 0, pg_enable_utf8 => 1 }
#			    ) or die $DBI::errstr;
#    $db->do ("SET TRANSFORM_NULL_EQUALS to ON") or die $DBI::errstr;

#    my $query = $db->prepare ($Peeves_config{'Chado_query'});
#    $query->execute();
#    my $current_chado = ($query->fetchall_arrayref())->[0]->[0];
#    defined $current_chado or die "Can't find a current production instance of Chado\n";
#    $query->finish();
#    $db->disconnect;

# Then, having found out the current production instance, place its name into the config variable and open a
# connection to that instance.

    #$Peeves_config{'Chado_instance'} = 'explore_chado';
#    print "CURRENT CHADO is $current_chado\n";
    our $chado = DBI->connect ("dbi:Pg:dbname=$Peeves_config{'Chado_db'};" .
			       "host=$Peeves_config{'Chado_host'};" .
			       "port=$Peeves_config{'Chado_port'}",
			       $Peeves_config{'Chado_user'},
			       $Peeves_config{'Chado_pass'},
			       { RaiseError => 1, AutoCommit => 0, pg_enable_utf8 => 1 }
			       ) or die $DBI::errstr;
    $chado->do ("SET TRANSFORM_NULL_EQUALS to ON") or die $DBI::errstr;

# Finally, prepare all the pre-defined queries which might be used later.

    set_up_chado_queries ();
}

sub chat_to_chado (@)		# Ask Chado the prepared query keyed by the first arg, parameters in remaining args.
{
    my $query = shift;
    my $arg = 1;
    $prepared_queries{$query}->bind_param ($arg++, shift) while (@_);
    $prepared_queries{$query}->execute ();
    return $prepared_queries{$query}->fetchall_arrayref();		# What's in its pocketses?
}

# Shut down the Chado connection, first by clearing all the prepared queries and then by disconnecting.

sub close_down_chado ()
{
    foreach my $sth (values %prepared_queries)
    {
	$sth->finish();
    }
    $chado->disconnect;
}

sub set_up_chado_queries ()
{

# Pub and minipub block

    $prepared_queries{'pub_from_id'}	       = $chado->prepare ('SELECT is_obsolete FROM pub WHERE uniquename=?;');
    $prepared_queries{'pub_title_from_id'}     = $chado->prepare ('SELECT title FROM pub WHERE uniquename=?;');
    $prepared_queries{'pub_id_from_title'}     = $chado->prepare ('SELECT uniquename FROM pub WHERE title=?;');
    $prepared_queries{'pub_date_from_id'}      = $chado->prepare ('SELECT pyear FROM pub WHERE uniquename=?;');
    $prepared_queries{'pub_place_from_id'}     = $chado->prepare ('SELECT pubplace FROM pub WHERE uniquename=?;');
    $prepared_queries{'pub_publisher_from_id'} = $chado->prepare ('SELECT publisher FROM pub WHERE uniquename=?;');
    $prepared_queries{'pub_series_from_id'}    = $chado->prepare ('SELECT series_name FROM pub WHERE uniquename=?;');
    $prepared_queries{'pub_voltitle_from_id'}  = $chado->prepare ('SELECT volumetitle FROM pub WHERE uniquename=?;');
    $prepared_queries{'pub_miniref_from_id'}   = $chado->prepare ('SELECT miniref FROM pub WHERE uniquename=?;');
    $prepared_queries{'pub_id_from_miniref'}   = $chado->prepare ('SELECT uniquename FROM pub WHERE miniref=?;');
    $prepared_queries{'pub_pubtype'}	       = $chado->prepare ('SELECT name FROM cvterm c, pub p
								   WHERE p.uniquename=? AND p.type_id=c.cvterm_id;');
    $prepared_queries{'pub_pages'}	       = $chado->prepare ('SELECT pages FROM pub WHERE uniquename=?;');
    $prepared_queries{'pub_issue'}	       = $chado->prepare ('SELECT issue FROM pub WHERE uniquename=?;');
    $prepared_queries{'pub_volume'}	       = $chado->prepare ('SELECT volume FROM pub WHERE uniquename=?;');
    $prepared_queries{'pub_abbr_to_multipub'}  = $chado->prepare ('SELECT uniquename FROM pub WHERE miniref=?;');
    $prepared_queries{'pub_URL'}	       = $chado->prepare ('SELECT pp.value
								   FROM pub p, pubprop pp, cvterm c
								   WHERE p.uniquename=?
								   AND p.pub_id=pp.pub_id
								   AND c.cvterm_id=pp.type_id
								   AND c.name=\'URL\';');
    $prepared_queries{'pub_languages'}	       = $chado->prepare ('SELECT pp.value
								   FROM pub p, pubprop pp, cvterm c
								   WHERE p.uniquename=?
								   AND p.pub_id=pp.pub_id
								   AND c.cvterm_id=pp.type_id
								   AND c.name=\'languages\';');
    $prepared_queries{'pub_abs_languages'}     = $chado->prepare ('SELECT pp.value
								   FROM pub p, pubprop pp, cvterm c
								   WHERE p.uniquename=?
								   AND p.pub_id=pp.pub_id
								   AND c.cvterm_id=pp.type_id
								   AND c.name=\'abstract_languages\';');
    $prepared_queries{'pub_files'}	       = $chado->prepare ('SELECT pp.value
								   FROM pub p, pubprop pp, cvterm c
								   WHERE p.uniquename=?
								   AND p.pub_id=pp.pub_id
								   AND c.cvterm_id=pp.type_id
								   AND c.name=\'deposited_files\'
								   ORDER BY pp.rank;');
    $prepared_queries{'pub_authors'}	       = $chado->prepare ('SELECT pa.surname, pa.givennames
								   FROM pubauthor pa, pub p
								   WHERE p.uniquename=?
								   AND p.pub_id=pa.pub_id
								   ORDER BY pa.rank;');
    $prepared_queries{'multipub_of_pub'}       = $chado->prepare ('SELECT p2.uniquename
								   FROM pub p, pub_relationship pr, pub p2, cvterm c
								   WHERE p.uniquename=?
								   AND pr.subject_id=p.pub_id
								   AND pr.object_id=p2.pub_id
								   AND c.cvterm_id=pr.type_id
								   AND c.name=\'published_in\';');
    $prepared_queries{'pub_journal_from_FBrf'} = $chado->prepare ('SELECT p2.miniref
								   FROM pub p, pub_relationship pr, pub p2, cvterm c
								   WHERE p.uniquename=?
								   AND pr.subject_id=p.pub_id
								   AND pr.object_id=p2.pub_id
								   AND c.cvterm_id=pr.type_id
								   AND c.name=\'published_in\';');
    $prepared_queries{'pub_abbr_to_pub_abbr'}  = $chado->prepare ('SELECT miniref FROM pub WHERE miniref=?;');

    $prepared_queries{'pub_accession'}	      = $chado->prepare ('SELECT dbxref.accession
								  FROM pub, pub_dbxref, dbxref, db
								  WHERE pub.uniquename=? 
								  AND pub.pub_id=pub_dbxref.pub_id
								  AND pub_dbxref.dbxref_id=dbxref.dbxref_id
							 	  AND dbxref.db_id=db.db_id
								  AND db.name=?;');

# Generic symbol<->id block

# feature (e.g. gene, allele, etc.)

    $prepared_queries{'feature_symbol_from_id'} = $chado->prepare ('SELECT DISTINCT s.synonym_sgml, f.is_obsolete
    								  							    FROM feature f, feature_synonym fs, synonym s, cvterm cvt
    								  							    WHERE f.feature_id = fs.feature_id
    								  							    AND fs.synonym_id = s.synonym_id
    								  							    AND fs.is_current = \'t\'
    								  							    AND fs.is_internal = \'f\'
    								  							    AND s.type_id = cvt.cvterm_id
    								  							    AND cvt.name = \'symbol\'
    								  							    AND f.is_obsolete = \'f\'
    								  							    AND f.uniquename=?;');

    $prepared_queries{'feature_id_from_symbol'} = $chado->prepare ('SELECT DISTINCT f.uniquename, f.is_obsolete
    								  								FROM feature f, feature_synonym fs, synonym s, cvterm cvt
    								  								WHERE f.feature_id = fs.feature_id
    								  								AND fs.synonym_id = s.synonym_id
    								  								AND fs.is_current = \'t\'
    								  								AND fs.is_internal = \'f\'
    								  								AND s.type_id = cvt.cvterm_id
    								  								AND cvt.name = \'symbol\'
    								  								AND f.is_obsolete = \'f\'
    								  								AND s.synonym_sgml=?;');

    $prepared_queries{'simple_feature_symbol_from_id'} = $chado->prepare ('SELECT name,is_obsolete FROM feature WHERE uniquename=?;');
    $prepared_queries{'simple_feature_id_from_symbol'} = $chado->prepare ('SELECT uniquename,is_obsolete FROM feature WHERE name=?;');


# query to see if current fullname - gets back the sgml version so may need to decode

    $prepared_queries{'feature_fullname_from_id'} = $chado->prepare ('SELECT distinct(s.synonym_sgml)
								  FROM feature f, feature_synonym fs, synonym s, cvterm cvt
								  WHERE f.feature_id = fs.feature_id
								  AND fs.synonym_id = s.synonym_id
								  AND fs.is_current = \'t\'
								  AND fs.is_internal = \'f\'
								  AND s.type_id = cvt.cvterm_id
								  AND cvt.name = \'fullname\'
								  AND f.is_obsolete = \'f\'
								  AND f.uniquename=?;');

# library

    $prepared_queries{'library_symbol_from_id'} = $chado->prepare ('SELECT DISTINCT s.synonym_sgml, l.is_obsolete
    								  							    FROM library l, library_synonym ls, synonym s, cvterm cvt
    								  							    WHERE l.library_id = ls.library_id
    								  							    AND ls.synonym_id = s.synonym_id
    								  							    AND ls.is_current = \'t\'
    								  							    AND ls.is_internal = \'f\'
    								  							    AND s.type_id = cvt.cvterm_id
    								  							    AND cvt.name = \'symbol\'
    								  							    AND l.is_obsolete = \'f\'
    								  							    AND l.uniquename=?;');

    $prepared_queries{'library_id_from_symbol'} = $chado->prepare ('SELECT DISTINCT l.uniquename, l.is_obsolete
    								  								FROM library l, library_synonym ls, synonym s, cvterm cvt
    								  								WHERE l.library_id = ls.library_id
    								  								AND ls.synonym_id = s.synonym_id
    								  								AND ls.is_current = \'t\'
    								  								AND ls.is_internal = \'f\'
    								  								AND s.type_id = cvt.cvterm_id
    								  								AND cvt.name = \'symbol\'
    								  								AND l.is_obsolete = \'f\'
    								  								AND s.synonym_sgml=?;');

	$prepared_queries{'library_type_from_id'} = $chado->prepare ('SELECT cv.name
								  FROM library l, cvterm cv
								  WHERE l.uniquename=?
								  AND l.is_obsolete = \'f\'
								  AND l.type_id = cv.cvterm_id;');

# gene group
    $prepared_queries{'grp_symbol_from_id'} = $chado->prepare ('SELECT DISTINCT s.synonym_sgml, g.is_obsolete
    								  							    FROM grp g, grp_synonym gs, synonym s, cvterm cvt
    								  							    WHERE g.grp_id = gs.grp_id
    								  							    AND gs.synonym_id = s.synonym_id
    								  							    AND gs.is_current = \'t\'
    								  							    AND gs.is_internal = \'f\'
    								  							    AND s.type_id = cvt.cvterm_id
    								  							    AND cvt.name = \'symbol\'
    								  							    AND g.is_obsolete = \'f\'
    								  							    AND g.uniquename=?;');

    $prepared_queries{'grp_id_from_symbol'} = $chado->prepare ('SELECT DISTINCT g.uniquename, g.is_obsolete
    								  								FROM grp g, grp_synonym gs, synonym s, cvterm cvt
    								  								WHERE g.grp_id = gs.grp_id
    								  								AND gs.synonym_id = s.synonym_id
    								  								AND gs.is_current = \'t\'
    								  								AND gs.is_internal = \'f\'
    								  								AND s.type_id = cvt.cvterm_id
    								  								AND cvt.name = \'symbol\'
    								  								AND g.is_obsolete = \'f\'
    								  								AND s.synonym_sgml=?;');


# humanhealth
    $prepared_queries{'humanhealth_symbol_from_id'} = $chado->prepare ('SELECT DISTINCT s.synonym_sgml, h.is_obsolete
    								  							    FROM humanhealth h, humanhealth_synonym hs, synonym s, cvterm cvt
    								  							    WHERE h.humanhealth_id = hs.humanhealth_id
    								  							    AND hs.synonym_id = s.synonym_id
    								  							    AND hs.is_current = \'t\'
    								  							    AND hs.is_internal = \'f\'
    								  							    AND s.type_id = cvt.cvterm_id
    								  							    AND cvt.name = \'symbol\'
    								  							    AND h.is_obsolete = \'f\'
    								  							    AND h.uniquename=?;');

    $prepared_queries{'humanhealth_id_from_symbol'} = $chado->prepare ('SELECT DISTINCT h.uniquename, h.is_obsolete
    								  								FROM humanhealth h, humanhealth_synonym hs, synonym s, cvterm cvt
    								  								WHERE h.humanhealth_id = hs.humanhealth_id
    								  								AND hs.synonym_id = s.synonym_id
    								  								AND hs.is_current = \'t\'
    								  								AND hs.is_internal = \'f\'
    								  								AND s.type_id = cvt.cvterm_id
    								  								AND cvt.name = \'symbol\'
    								  								AND h.is_obsolete = \'f\'
    								  								AND s.synonym_sgml=?;');

# cell line
    $prepared_queries{'cell_line_name_from_id'} = $chado->prepare ('SELECT DISTINCT s.synonym_sgml
    								  							    FROM cell_line cl, cell_line_synonym cls, synonym s, cvterm cvt
    								  							    WHERE cl.cell_line_id = cls.cell_line_id
    								  							    AND cls.synonym_id = s.synonym_id
    								  							    AND cls.is_current = \'t\'
    								  							    AND cls.is_internal = \'f\'
    								  							    AND s.type_id = cvt.cvterm_id
    								  							    AND cvt.name = \'symbol\'
    								  							    AND cl.uniquename=?;');

    $prepared_queries{'cell_line_id_from_name'} = $chado->prepare ('SELECT DISTINCT cl.uniquename
    								  								FROM cell_line cl, cell_line_synonym cls, synonym s, cvterm cvt
    								  								WHERE cl.cell_line_id = cls.cell_line_id
    								  								AND cls.synonym_id = s.synonym_id
    								  								AND cls.is_current = \'t\'
    								  								AND cls.is_internal = \'f\'
    								  								AND s.type_id = cvt.cvterm_id
    								  								AND cvt.name = \'symbol\'
    								  								AND s.synonym_sgml=?;');
# strain
    $prepared_queries{'strain_symbol_from_id'} = $chado->prepare ('SELECT DISTINCT s.synonym_sgml, st.is_obsolete
    								  							    FROM strain st, strain_synonym sts, synonym s, cvterm cvt
    								  							    WHERE st.strain_id = sts.strain_id
    								  							    AND sts.synonym_id = s.synonym_id
    								  							    AND sts.is_current = \'t\'
    								  							    AND sts.is_internal = \'f\'
    								  							    AND s.type_id = cvt.cvterm_id
    								  							    AND cvt.name = \'symbol\'
    								  							    AND st.is_obsolete = \'f\'
    								  							    AND st.uniquename=?;');

    $prepared_queries{'strain_id_from_symbol'} = $chado->prepare ('SELECT DISTINCT st.uniquename, st.is_obsolete
    								  								FROM strain st, strain_synonym sts, synonym s, cvterm cvt
    								  								WHERE st.strain_id = sts.strain_id
    								  								AND sts.synonym_id = s.synonym_id
    								  								AND sts.is_current = \'t\'
    								  								AND sts.is_internal = \'f\'
    								  								AND s.type_id = cvt.cvterm_id
    								  								AND cvt.name = \'symbol\'
    								  								AND st.is_obsolete = \'f\'
    								  								AND s.synonym_sgml=?;');


# interaction

# needs to be named this way (even though a symbol isn't really involved) so that can use
# the standard 'chado_types' loop of valid_symbol 
    $prepared_queries{'interaction_id_from_symbol'} = $chado->prepare ('SELECT uniquename, is_obsolete FROM interaction WHERE uniquename=?;');


# Allele specific block

    $prepared_queries{'associated_with_FBal'} = $chado->prepare ('SELECT f2.uniquename
								  FROM feature f1, feature f2,
								       feature_relationship fr, cvterm cv
								  WHERE f1.uniquename=?
								  AND f1.feature_id = fr.object_id
								  AND f2.feature_id = fr.subject_id
								  AND cv.cvterm_id=fr.type_id
								  AND cv.name=\'associated_with\';');

# Organism information


# used in valid_symbol as only requires one argument for query
# test for validity of species abbreviation, storing 'genus species' as the result
    $prepared_queries{'chado_species_abbreviation'} = $chado->prepare ('SELECT abbreviation, genus, species
								  FROM organism
								  WHERE abbreviation=?;');


# retrieve taxgroup information using species abbreviation as the argument
    $prepared_queries{'chado_species_taxgroup'} = $chado->prepare ('SELECT op.value
								  FROM organism o, organismprop op, cvterm cvt, cv cv
								  WHERE o.organism_id = op.organism_id
								  AND op.type_id = cvt.cvterm_id
								  AND cvt.name = \'taxgroup\'
								  AND cvt.is_obsolete = \'0\'
								  AND cvt.cv_id = cv.cv_id
								  AND cv.name = \'property type\'
								  AND o.abbreviation=?;');

# used in valid_species as requires two arguments for query
# simple test for validity of organism
    $prepared_queries{'chado_full_species_validity'} = $chado->prepare ('SELECT genus, species
								  FROM organism
								  WHERE genus=?
								  AND species=?;');


# retrieve species abbreviation for the organism using genus and species as the argument
    $prepared_queries{'chado_full_species_abbreviation'} = $chado->prepare ('SELECT abbreviation
								  FROM organism
								  WHERE genus=?
								  AND species=?;');

# retrieve common name for the organism using genus and species as the argument
    $prepared_queries{'chado_full_common_name'} = $chado->prepare ('SELECT common_name
								  FROM organism
								  WHERE genus=?
								  AND species=?;');

# retrieve taxon id for the organism using genus and species as the argument
    $prepared_queries{'chado_full_taxon'} = $chado->prepare ('SELECT dbx.accession
								  FROM organism o, dbxref dbx, organism_dbxref od, db db
								  WHERE o.organism_id = od.organism_id
								  AND dbx.dbxref_id = od.dbxref_id
								  AND od.is_current = \'t\'
								  AND dbx.db_id = db.db_id
								  AND db.name = \'NCBITaxon\'
								  AND genus=?
								  AND species=?;');


# retrieve 'official database' for the organism using genus and species as the argument


    $prepared_queries{'chado_full_official_db'} = $chado->prepare ('SELECT op.value
								  FROM organism o, organismprop op, cvterm cvt, cv cv
								  WHERE o.organism_id = op.organism_id
								  AND op.type_id = cvt.cvterm_id
								  AND cvt.name = \'official_db\'
								  AND cvt.is_obsolete = \'0\'
								  AND cvt.cv_id = cv.cv_id
								  AND cv.name = \'property type\'
								  AND genus=?
								  AND species=?;');
								  


# Information from database table

	$prepared_queries{'chado database name'} = $chado->prepare ('SELECT name
								  FROM db
								  WHERE name=?;');


	$prepared_queries{'chado database description'} = $chado->prepare ('SELECT description
								  FROM db
								  WHERE name=?;');

	$prepared_queries{'chado database url'} = $chado->prepare ('SELECT url
								  FROM db
								  WHERE name=?;');
								  
	$prepared_queries{'chado database urlprefix'} = $chado->prepare ('SELECT urlprefix
								  FROM db
								  WHERE name=?;');


# Experimental tool information

## gene level 'common_tool_uses'

	$prepared_queries{'common_tool_uses'} =  $chado->prepare ('SELECT cvt.name
								  FROM feature f, cvterm cvt,
 								  feature_cvterm fc, cvterm cvt2,
								  feature_cvtermprop fcvtp
								  WHERE f.feature_id = fc.feature_id
								  AND f.uniquename=?
								  AND cvt.cvterm_id = fc.cvterm_id
								  AND fc.is_not = \'f\'
								  AND fc.feature_cvterm_id = fcvtp.feature_cvterm_id
								  AND fcvtp.type_id = cvt2.cvterm_id
								  AND cvt2.name = \'common_tool_uses\';');
## Queries for additional checks for new FBco symbols
## tool field information (can be used for FBal or FBtp)
## need to specify FBal/FBtp id and type of feature_relationship

	$prepared_queries{'tool_relationship'} = $chado->prepare ('SELECT f2.uniquename
								  FROM feature f1, feature f2,
								       feature_relationship fr, cvterm cv
								  WHERE f1.uniquename=?
								  AND f1.feature_id = fr.subject_id
								  AND f2.feature_id = fr.object_id
								  AND cv.cvterm_id=fr.type_id
								  AND cv.name=?;');


## query to get inserted elements (can be FBtp or FBte) for alleles that are associated with an insertion
## need to provide FBal number
	$prepared_queries{'inserted_element'} = $chado->prepare ('SELECT f3.uniquename
								  FROM feature f1, feature f2, feature f3,
								       feature_relationship fr, cvterm cv,
								       feature_relationship fr2, cvterm cv2
								  WHERE f1.uniquename =?
								  AND f1.feature_id = fr.subject_id
								  AND f2.feature_id = fr.object_id
								  AND f2.uniquename like \'FBti%\'
								  AND cv.cvterm_id=fr.type_id
								  AND cv.name=\'associated_with\'
								  AND f2.feature_id = fr2.subject_id
								  AND f3.feature_id = fr2.object_id
								  AND cv2.cvterm_id=fr2.type_id
								  AND cv2.name=\'producedby\';');

## get tool uses information
	$prepared_queries{'tool_uses'} = $chado->prepare ('SELECT cvt.name
							   FROM feature f, cvterm cvt, feature_cvterm fcvt, feature_cvtermprop fcp, cvterm cvt2, cv
							   WHERE fcvt.feature_id = f.feature_id
							   AND fcvt.feature_cvterm_id = fcp.feature_cvterm_id
							   AND fcp.type_id = cvt2.cvterm_id
							   AND cvt2.name = \'tool_uses\'
							   AND f.uniquename =?
							   AND fcvt.cvterm_id = cvt.cvterm_id
							   AND cvt2.cv_id = cv.cv_id
							   AND cv.name = \'feature_cvtermprop type\';');

## SO

	$prepared_queries{'SO_annotation'} =  $chado->prepare ('SELECT cvt.name
								  FROM feature f, cvterm cvt,
 								  feature_cvterm fc, cv cv
								  WHERE f.feature_id = fc.feature_id
								  AND f.uniquename=?
								  AND cvt.cvterm_id = fc.cvterm_id
								  AND fc.is_not = \'f\'
								  AND cvt.cv_id = cv.cv_id
								  AND cv.name = \'SO\';');


}


1;				# Boilerplate.
