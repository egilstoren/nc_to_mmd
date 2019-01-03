#!/usr/bin/perl -w
use strict;
use Encode;
my $debug = "";
#
#  Usage
#
my $usagetext = <<'HERE_TARGET';

Usage:

   nc_to_mmd.pl [options] [item1 item2 item3 ...]

   If no options, the items on the command line are assumed to be either netCDF files or thredds DAS URLs. 
   An MMD xml file is constructed based on the metadata found in the netCDF files or URLs. This MMD xml file is 
   written to standard output. If no options and no items are found on the commeand line, this usage text is
   written to standard output.

   The following options will modify this behaviour:

   --itemlist=filename

     The file with the given filename contains a list of items (netCDF files or URLs separated by newlines). The MMD 
     xml file will be based on these items (in addition to any items given on the command line).

   --output=filename

     The resulting MMD xml will be written to the named file.

   --force=filename

     The filename is the name of a text file containing metadata that will be forced into the MMD xml. This file
     (the force document) containes lines of two types:

     names = value
     names .= value

     'names' is a sequence of element names in the MMD xml document that defines a metadata value. For example,
     the MMD xml may contain elements like this:

     <mmd:project>
        <mmd:short_name>IPY-THORPEX</mmd:short_name>
        <mmd:long_name>IPY-THORPEX project</mmd:long_name>
     </mmd:project>

     Then "project short_name" will be the 'names' that define "IPY-THORPEX". If you want to force another value
     (e.g. XXX) into the MMD xml to substitute for "IPY THORPEX", you may include into the force document:

     project short_name = XXX

     Using the ".=" variant will append the new value to any value found in the harvested metadata.

   --collection=collectioncode

     Where collectioncode is a collection keyword. The default collection keyword is ADC.

   --help

     If this option is found, a more elaborate help text is written on standard output.

   --documentation

     If this option is found, a comprehensive program documentation is written to standard output

   --

     Indicates end of options. Any further argument will be taken as a file name, even if it starts with '-'.

HERE_TARGET
#
#  Helptext
#
my $helptext = <<'HERE_TARGET';
The following options may help to investigate why the resulting MMD is not containing expected metadata:

   --listglobatts

     With this option, all global attribute names found in any of the netCDF files or URLs will be written to 
     standard output. No MMD xml file will be produced.

   --showglobatt=name

     Write all distinct values of the global attrbute with the given name, found in any of the netCDF
     files/URLs, to the standard output. No MMD xml file will be produced.

The production of the MMD is gowerned by a set of documents. Default versions of these documents are part
of this program. It is however possible to use modified versions of the documents. To do this, you must first
print a default document to a file, and then modify it according to your wishes. Then you must tell the program
to use the modified document. All this can be achieved by the following options:

   --showdoc=name

     Write the named document to standard output and exit. Name can be any of the following document names:
     template: The default template document
     rules: The default rules document
     vocabulary: The default vocabulary document
     translations: The default translations document
     classify: The default classify document
     reportxsd: The report XSD schema (this document is only for information)

   --usetemplate=filename

     Use the template document in the given file instead of the default template document

   --userules=filename

     Use the rules document in the given file instead of the default rules document

   --usevocabulary=filename

     Use the vocabulary document in the given file instead of the default vocabulary document

   --usetranslations=filename

     Use the translations document in the given file instead of the default vocabulary document

   --useclassify=filename

     Use the classify document in the given file instead of the default classify document

The following debug option is mainly intended for personell whishing to change/improve the program:

   --debug=code

     Output debug info to standard output. Code must be one of: allhashkeys allhashvalues classify convention coord_vars 
     standard_names createmmd elements namesarr options showtpl splitexact templatearr

HERE_TARGET
my %programdoc = ();
my $classify = <<'EOF';
#
# Classify document
#
# This document is used to find which metadata convention is used in a netCDF file. A simple syntax is used:
#
#    convention_name: list_of_global_attribute_names
#
# The convention_name must start on a new line at the first character position. The list_of_global_attribute_names
# contains a blank-separated list of global attribute names typically used in netCDF files following the given
# convention. This list may comprise several lines; continuation lines must start with a space character.
#
# This document is also used to mark which global attributes are mandatory. If mandatory, The string "(M)" is appended to
# the global attribute name.
#
ACDD: title(M) id naming_authoritiy keywords(M) keywords_vocabulary summary(M) comment date_created date_content_modified 
      date_values_modified creator_name creator_url creator_email publisher_name publisher_email publisher_url project 
      processing_level acknowledgement geospatial_bounds geospatial_bounds_crs geospatial_bounds_vertical_crs 
      geospatial_lat_min 
      geospatial_lat_max(M) geospatial_lon_min(M) geospatial_lon_max(M) geospatial_vertical_min geospatial_vertical_max
      geospatial_vertical_positive time_coverage_start(M) time_coverage_end(M) time_coverage_duration time_coverage_resolution
      standard_name_vocabulary license source Conventions(M)
MET:  title(M) keywords(M) abstract(M) PI_name contact project_name quality_index southernmost_latitude(M) northernmost_latitude(M)
      westernmost_longitude(M) easternmost_longitude(M) minimum_altitude maximum_altitude start_date(M) stop_date(M) 
      distribution_statement activity_type product_name product_version software_version references area grid_projection 
      latitude_resolution longitude_resolution field_type Platform_name operational_status gcmd_keywords Conventions(M)
EOF
my %mandatoryhash = ();
my $tplsequencedoc = <<'EOF';
#
# Template document
#
# This document contains templates for building the MMD xml.
#
# Each template is identified by a line starting with '='. Such lines has the following format:
#
#    =name repeat-rules
#
# where 'name' is the name that identifies the template and 'repeat-rules' comprise three blank-separated
# fields explained below.
#
# The template itself is all lines following the identification line until the next identification line
# (or end of document). The template is subdivided into line groups. Each line group is identified by a
# digit (1-9) in the first character column on each line. Lines with the same digit belong to the same
# line group.
#
# The 'repeat-rules' part of the identification line contains references to line groups. The three
# blank-separated fields of the 'repeat-rules' part has the following content:
#
#    BEGIN - Identifies the line group that comprise the beginning of the xml element that is produced by
#            the template.
#
#    END   - Identifies the line group that comprise the end of the xml element that is produced by the
#            template.
#
#    LIST  - This field describes what should be produced between BEGIN and END. In its simplest form, it
#            contains two subfields separated by ':'. The first subfield is a repetition code (see below),
#            the second subfield identifies a line group. The LIST field may also contain several of these
#            ':'-separated entities. If so, these entities are separated by '-'.
#
# The BEGIN and END fields will either contain a single digit identifying a line group, or the text "empty",
# meaning that no text should be produced at the beginning or end of the xml element. In this case, the whole
# element is described by the LIST field.
# 
# The lines within a template comprise three fields:
#
#    - Line group digit
#    - XML text
#    - Repetition code
#
# The XML text is separated from the line group digit and the repetition code by one space character.
# The XML text itself may contain spaces.
#
# The repetition code is one of the following:
#
#    M   - The corresponding line or linegroup is mandatory, but not repeatable
#    MR  - The line or linegroup is mandatory and can be repeated
#    O   - The line or linegroup is optional, but not repeatable
#    OR  - The line or linegroup is optional and repeatable
#
# For lines within a template, an extra repetion code can be used:
#
#    OX   - The line is optional. If metadata is found for this line, this should not imply
#           that the correspnding line group is added to the MMD xml. Only if metadata for other
#           lines in the line group are also found (lines not having the OX repcode), the line
#           group will be added to the MMD xml.
#
# The XML text may contain placeholders that will be substituted by metadata content taken from the netCDF
# files. These placeholders take the form '==id==', where id is an identifier used in the rules document.
#
=start empty empty M:1
1 <?xml version="1.0" encoding="UTF-8"?> M
1 <mmd:mmd xmlns:mmd="http://www.met.no/schema/mmd" xmlns:gml="http://www.opengis.net/gml"> M
=metadata_identifier empty empty M:1
1  <mmd:metadata_identifier>==metadata_identifier==</mmd:metadata_identifier> M
=title empty empty MR:1
1  <mmd:title xml:lang="en">==title==</mmd:title> MR
=abstract empty empty M:1
1  <mmd:abstract xml:lang="en">==abstract==</mmd:abstract> M
=metadata_status empty empty M:1
1  <mmd:metadata_status>Active</mmd:metadata_status> M
=dataset_production_status empty empty M:1
1  <mmd:dataset_production_status>==dataset_production_status==</mmd:dataset_production_status> M
=collection empty empty M:1
1  <mmd:collection>==collection==</mmd:collection> M
=last_metadata_update empty empty M:1
1  <mmd:last_metadata_update>==last_metadata_update==</mmd:last_metadata_update> M
=temporal_extent empty empty M:1
1  <mmd:temporal_extent> M
1    <mmd:start_date>==start_date==</mmd:start_date> M
1    <mmd:end_date>==end_date==</mmd:end_date> O
1  </mmd:temporal_extent> M
=iso_topic_category empty empty MR:1
1  <mmd:iso_topic_category>==iso_topic_category==</mmd:iso_topic_category> MR
=keywords.1 1 3 O:2
1  <mmd:keywords vocabulary="none"> O
2    <mmd:keyword>==keyword==</mmd:keyword> MR
3  </mmd:keywords> O
=keywords.2 1 3 O:2
1  <mmd:keywords vocabulary="Climate and Forecast Standard Names"> O
2    <mmd:keyword>==keyword==</mmd:keyword> MR
3  </mmd:keywords> O
=keywords.3 1 3 O:2
1  <mmd:keywords vocabulary="Global Change Master Directory"> O
2    <mmd:keyword>==gcmd_keywords==</mmd:keyword> MR
3  </mmd:keywords> O
=dataset_language empty empty M:1
1  <mmd:dataset_language>en</mmd:dataset_language> M
=operational_status empty empty O:1
1  <mmd:operational_status>==operational_status==</mmd:operational_status> M
=geographic_extent 1 3 M:2
1  <mmd:geographic_extent> M
2    <mmd:rectangle> M
2      <mmd:north>==north==</mmd:north> M
2      <mmd:south>==south==</mmd:south> M
2      <mmd:east>==east==</mmd:east> M
2      <mmd:west>==west==</mmd:west> M
2    </mmd:rectangle> M
3  </mmd:geographic_extent> M
=access_constraint empty empty O:1
1  <mmd:access_constraint>==access_constraint==</mmd:access_constraint> O
=use_constraint empty empty O:1
1  <mmd:use_constraint>==use_constraint==</mmd:use_constraint> O
=project empty empty O:1
1  <mmd:project> O
1    <mmd:short_name>==short_name==</mmd:short_name> M
1    <mmd:long_name>==long_name==</mmd:long_name> M
1  </mmd:project> O
=activity_type empty empty OR:1
1  <mmd:activity_type>==activity_type==</mmd:activity_type> OR
=instrument empty empty OR:1
1  <mmd:instrument> OR
1    <mmd:short_name>==short_name==</mmd:short_name> M
1    <mmd:long_name>==long_name==</mmd:long_name> M
1  </mmd:instrument> OR
=platform empty empty OR:1
1  <mmd:platform> OR
1    <mmd:short_name>==short_name==</mmd:short_name> M
1    <mmd:long_name>==long_name==</mmd:long_name> M
1  </mmd:platform> OR
=related_information empty empty OR:1
1  <mmd:related_information OR
1    <mmd:type>Project home page</mmd:type> M
1    <mmd:resource>==metadata_link==</mmd:resource> M
1  </mmd:related_information> OR
=personnel.1 empty empty OR:1
1  <mmd:personnel> OR
1    <mmd:role>Investigator</mmd:role> M
1    <mmd:name>==name==</mmd:name> M
1    <mmd:organisation>==organisation==</mmd:organisation> OX
1    <mmd:email>==email==</mmd:email> M
1    <mmd:phone/> M
1    <mmd:fax/> M
1  </mmd:personnel> OR
=personnel.2 empty empty OR:1
1  <mmd:personnel> OR
1    <mmd:role>Technical contact</mmd:role> M
1    <mmd:name>==name==</mmd:name> M
1    <mmd:organisation>==organisation==</mmd:organisation> OX
1    <mmd:email>==email==</mmd:email> M
1    <mmd:phone/> M
1    <mmd:fax/> M
1  </mmd:personnel> OR
=personnel.3 empty empty OR:1
1  <mmd:personnel> OR
1    <mmd:role>Publisher</mmd:role> M
1    <mmd:name>==name==</mmd:name> M
1    <mmd:email>==email==</mmd:email> M
1    <mmd:phone/> M
1    <mmd:fax/> M
1  </mmd:personnel> OR
=data_access empty empty OR:1
1  <mmd:data_access> OR
1    <mmd:name/> O
1    <mmd:type>==type==</mmd:type> M
1    <mmd:description/> O
1    <mmd:resource>==resource==</mmd:resource> M
1    <mmd:wms_layers> O
1      <mmd:wms_layer>==wms_layer==</mmd:wms_layer> MR
1    </mmd:wms_layers> O
1  </mmd:data_access> OR
=reference empty empty OR:1
1  <mmd:reference type="fields"> OR
1    <mmd:title>==title==</mmd:title> M
1    <mmd:author>==author==</mmd:author> M
1    <mmd:online_resource>==online_resource==</mmd:online_resource> O
1  </mmd:reference> OR
=data_center empty empty O:1
1  <mmd:data_center> O
1    <mmd:data_center_name> M
1      <mmd:short_name>==short_name==</mmd:short_name> M
1      <mmd:long_name>==long_name==</mmd:long_name> M
1    </mmd:data_center_name> M
1    <mmd:data_center_url>==data_center_url==</mmd:data_center_url> O
1    <mmd:online_resource>==online_resource==</mmd:online_resource> O
1  </mmd:data_center> O
=end empty empty M:1
1 </mmd:mmd> M
EOF
my $rules = <<'EOF';
#
# Rules document
#
# The rules document describes how to find metadata content in the netCDF files that will be
# used in the MMD xml produced from the templates in the template document.
#
# The rules document is a sequence of rules. Each rule starts on a new line and has the text 'element '
# as the first eight characters. A rule may comprise several lines. Each of the continuation lines should
# start with a space.
#
# A rule has the following form:
#
#    element elementnames use use-clause
#
# where elementnames comprise one or more names of MMD xml elements. If only one element name is used in
# elementnames, this name identifies an element at the highest level in the element hierarchy within the
# MMD xml. i.e. an element having as parent the top-level <mmd:mmd ...>...</mmd:mmd> element. If several
# names are used in elementnames, each of the additional names has the element identified by the previous
# name on the line, as parent.
#
# The last name in elementnames will allways identify an element on the bottom of the hierachy, i.e. an 
# element without children elements. This last element name is used in the Template document to identify which
# rule to apply.
#
# The use-clause comprise a sequence of blank-separated fields. Each field starts with a keyword that identifies
# the type of the field. Then may follow several ':'-separated subfields depending on the field type. The following
# five field types are defined at present:
#
#    GATT               - After the GATT keyword follows ':'-separated subfields.
#                         The first subfield identifies the name of a global attribute inside a netCDF file.
#                         The value(s) to be used in the MMD xml are taken from this global attribute.
#
#                         The next subfield is a keyword telling how to handle multiple values. Multiple
#                         values may arise either from the same netCDF file (e.g comma-separated values) or
#                         from several netCDF files. The keyword has the following meaning:
#
#                           'any': Take any single value (not important which)
#                           'all': Take all values
#                           'max': Sort the values lexicographically and take the last
#                           'min': Sort the values lexicographically and take the first.
#
#                         Then may the following optional subfields appear:
#
#                           spliton="chars" where chars is a sequence of characters that separate individual parts
#                           of a value (e.g. ","). spliton="SPACE" will split on a single space character; spliton=" "
#                           will not work.
#
#                           linebreak="chars" where chars is a sequence of characters that indicates a line break.
#                           This subfield is used to preserve linebreaks within a single value.
#
#                         Several GATT fields may be used. They are sorted according to priority. If no global
#                         attribute corresponding to the first GATT field is found, the next GATT field is used etc.
#
#    STDNAME            - This field has no subfields.
#                         The values to be used in the MMD xml comprise all the CF standard names found in the
#                         netCDF files (or OpenDAP DAS documents). Standard names for typical coordinate variables
#                         are excluded (latitude, longitude, time).
#
#    EXTRACTDATE        - No subfields. This field must occur after a GATT
#                         field which presumably produce a time string starting with a date (like YYY-MM-DD). The
#                         EXTRACTDATE field will ensure that only the date string is preserved. Any time string
#                         will be discarded.
#
#    TRANSLATE          - One subfield: a word that corresponds to a word
#                         in the translations document. This word (typically an element name) identifies a translation
#                         table that is used to translate keywods from a different standard to MMD. This field must 
#                         occur after a GATT field that produce the original keyword that need translation.
#
#    COLLECTION         - Insert the collection keyword which may be given on the command line (default ADC).
#
#    NOTHING            - Do not use any rule. This field type will only ensure that an entry is defind in the elements
#                         hash.
#
element metadata_version use NOTHING
element metadata_identifier use NOTHING
element collection use COLLECTION
element title use GATT:title
element abstract use GATT:abstract:any:linebreak="\n" GATT:summary:any:linebreak="\n"
element last_metadata_update use
   GATT:date_content_modified:max
   GATT:date_values_modified:max
   GATT:date_update:max
   GATT:date_modified:max
   GATT:date_created:max
   GATT:creation_date:max
   GATT:date_issued:max
   EXTRACTDATE
element dataset_production_status use GATT:product_status
element operational_status use GATT:operational_status
element iso_topic_category use GATT:topiccategory:all:spliton="SPACE"
element temporal_extent start_date use GATT:time_coverage_start:min GATT:start_date:min EXTRACTDATE
element temporal_extent end_date use GATT:time_coverage_end:max GATT:stop_date:max EXTRACTDATE
element geographic_extent geographic_rectangle north use
   GATT:geospatial_lat_max
   GATT:northernmost_latitude
element geographic_extent geographic_rectangle south use
   GATT:geospatial_lat_min
   GATT:southernmost_latitude
element geographic_extent geographic_rectangle east use
   GATT:geospatial_lon_max
   GATT:easternmost_longitude
element geographic_extent geographic_rectangle west use
   GATT:geospatial_lon_min
   GATT:westernmost_longitude
element access_constraint use GATT:distribution_statement GATT:license
element use_constraint use GATT:distribution_statement GATT:license
element project short_name use GATT:project GATT:project_name GATT:project_id
element project long_name use GATT:project GATT:project_name GATT:project_id
element activity_type use GATT:activity_type GATT:source TRANSLATE:activity_type
element instrument long_name use GATT:instrument_type
element platform short_name use GATT:Platform_name
element platform long_name use GATT:Platform_name
element related_information recource use GATT:metadata_link
element keywords.1 vocabulary="none" keyword use GATT:keywords:all:spliton=","
element keywords.2 vocabulary="Climate and Forecast Standard Names" keyword use STDNAME
element keywords.3 vocabulary="Global Change Master Directory" gcmd_keywords use GATT:gcmd_keywords:all:spliton="NEWLINE"
element dataset_language use NOTHING
element personnel.1 name use GATT:creator_name GATT:PI_name GATT:creator
element personnel.1 email use GATT:creator_email
element personnel.1 organisation use GATT:institution
element personnel.1 phone use NOTHING
element personnel.1 fax use NOTHING
element personnel.2 name use NOTHING
element personnel.2 email use GATT:contact
element personnel.2 organisation use GATT:institution
element personnel.2 phone use NOTHING
element personnel.2 fax use NOTHING
element personnel.3 name use GATT:publisher_name
element personnel.3 email use GATT:publisher_email
element personnel.3 organisation use NOTHING
element personnel.3 phone use NOTHING
element personnel.3 fax use NOTHING
element data_access name use NOTHING
element data_access type use NOTHING
element data_access description use NOTHING
element data_access resource use NOTHING
element data_access wms_layers wms_layer use NOTHING
element reference title use GATT:references:all:spliton="NEWLINE"
element reference author use NOTHING
element reference online_resource use NOTHING
element data_center data_center_name short_name use NOTHING
element data_center data_center_name long_name use NOTHING
element data_center data_center_url use NOTHING
element data_center online_resource use NOTHING
EOF

my $vocabularies = <<'EOF';
#
#  Vocabulary document
#
#  Contains one or more vocabularies. Each vocabulary starts with a name (lines with no initial spaces).
#  Then follows the values (lines with initial spaces). The metadata from the nc-files that are assumed to
#  correspond to a value in a vocabulary, is converted to lovercase and compared to the lovercase versions
#  of the values. If a match is found, the matching vacabulary value is used in its original version. If
#  no match, the metadata is discarded.
#
iso_topic_category
   farming
   biota
   boundaries
   climatologyMeteorologyAtmosphere
   economy
   elevation
   environment
   geoscientificInformation
   health
   imageryBaseMapsEarthCover
   intelligenceMilitary
   inlandWaters
   location
   oceans
   planningCadastre
   society
   structure
   transportation
   utilitiesCommunications
dataset_production_status
   Planned
   In Work
   Complete
   Obsolete
EOF
my $translations = <<'EOF';
#
# Translations document
#
# Some netCDF files may follow standards that use other vocabularies than MMD. This document offer a
# possibility to translate metadata using these standards to MMD.
#
# The following syntax is used:
#
# 1. Lines starting with '#' are ignored
#
# 2. Lines starting with a letter introduce translations. Such lines contain one word that identifies a translation
#    table. This word is used in the rules document to refer to the translation table.
#
# 3. Following this line, comes the translation table itself. Each line in the table have the following syntax:
#
#    SPACE Original keyword -> Translated keyword 
#
#    SPACE represents one ore more space characters, '->' separates the original and translated keywords. Both
#    original and translated keywords may contain spaces. The original keyword must be in all lowercase letters.
#    They will match even if the extracted data contain uppercase letters.
#
activity_type
 earth observation satelite -> Space Borne Instrument
 land station -> In Situ Land-based station
 cruise -> In Situ Ship-based station
 moored instruments -> In Situ Ocean fixed station
 float -> In Situ Ocean moving station
 submersible -> In Situ Ocean moving station
 ice station -> In Situ Ice-based station
 interview -> Interview/Questionnaire
 questionnaire -> Interview/Questionnaire
 maps -> Maps/Charts/Photographs
 charts -> Maps/Charts/Photographs
 photographs -> Maps/Charts/Photographs
 model run -> Numerical Simulation
EOF
#
#  Report XSD document
#
my $reportxsd = <<'EOF';
<?xml version="1.0" encoding="UTF-8" ?>
<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
<xs:element name="report">
  <xs:complexType>
    <xs:sequence>
      <xs:element name="date" type="xs:string" minOccurs="1" maxOccurs="1"/>
      <xs:element name="options" minOccurs="1" maxOccurs="1">
        <xs:complexType>
          <xs:sequence>
            <xs:element name="opt" type="xs:string" minOccurs="0" maxOccurs="unbounded"/>
          </xs:sequence>
        </xs:complexType>
      </xs:element>
      <xs:element name="files" minOccurs="1" maxOccurs="1">
        <xs:complexType>
          <xs:sequence>
            <xs:element name="file" minOccurs="1" maxOccurs="unbounded">
              <xs:complexType>
                <xs:simpleContent>
                  <xs:extension base="xs:string">
                    <xs:attribute name="num" type="xs:string" />
                  </xs:extension>
                </xs:simpleContent>
              </xs:complexType>
            </xs:element>
          </xs:sequence>
        </xs:complexType>
      </xs:element>
      <xs:element name="messages" minOccurs="1" maxOccurs="1">
        <xs:complexType>
          <xs:sequence>
            <xs:element name="msg" minOccurs="0" maxOccurs="unbounded">
              <xs:complexType>
                <xs:simpleContent>
                  <xs:extension base="xs:string">
                    <xs:attribute name="type">
                      <xs:simpleType>
                        <xs:restriction base="xs:string">
                          <xs:enumeration value="INFO"/>
                          <xs:enumeration value="WARNING"/>
                          <xs:enumeration value="ERROR"/>
                        </xs:restriction>
                      </xs:simpleType>
                    </xs:attribute>
                  </xs:extension>
                </xs:simpleContent>
              </xs:complexType>
            </xs:element>
          </xs:sequence>
        </xs:complexType>
      </xs:element>
    </xs:sequence>
  </xs:complexType>
</xs:element>
</xs:schema>
EOF
#
#  Script for getting DAS document
#
my $getdasscript = <<'EOF';
#   !/bin/sh
   set -e
   wget --output-document=/tmp/das_document ==URL==
   if [ `wc -c /tmp/das_document | sed 's/ .*//'` -gt 200000 ]; then exit 1; fi
   exit 0
EOF
#
# Path to ncdump
# used for extracting metadata from the netCDF files:
#
my $ncdumpbin = 'ncdump';
#
#  Array @allfiles
#  used to collect all netCDF file names or URLs on the command line or found in the itemlist file.
#
my @allfiles = ();
#
# Options hash
#
my %options = ();
#
# Report hash
#
my %messages = ();
#
#  Initialize hash stdname_exceptions:
#
my %stdname_exceptions = ( latitude => 1,
   longitude => 1,
   time => 1,
   projection_x_coordinate => 1,
   projection_y_coordinate => 1,
);
my $allow_hyphens = 0;
my $item_type = "file";
my $collection = 'ADC';
my $force_doc = '';
#
#  Loop through all command line arguments
#
foreach my $arg (@ARGV) {
   if ($arg eq "--") {
      $allow_hyphens = 1;
   }
   elsif ($allow_hyphens) {
      push (@allfiles,$arg);
   }
   elsif ($arg =~ /^(--[^=]+)=(.*)$/) {
      $options{$1} = $2;
   }
   elsif ($arg =~ /^(--[^=]+)$/) {
      $options{$1} = "";
   }
   elsif ($arg =~ /^-[^-].*$/) {
      print ('Illegal option (use "--"): ' . $arg . "\n");
      exit;
   }
   else {
      push (@allfiles,$arg);
   }
}
if (exists($options{'--debug'})) {
   $debug = $options{'--debug'};
}
if ($debug eq "options") {
   foreach my $key (keys %options) {
      print ($key . ' = ' . $options{$key} . "\n");
   }
}
if (exists($options{'--itemlist'})) {
   my $listfilename = $options{'--itemlist'};
   unless (-r $listfilename) {die "Can not read from file: $listfilename\n";}
   open (LISTFILE,$listfilename);
      while (<LISTFILE>) {
         chomp($_);
         my $line = $_;
         push (@allfiles,$line);
      }
   close (LISTFILE);
}
if (exists($options{'--collection'})) {
   $collection = $options{'--collection'};
}
if (exists($options{'--showdoc'})) {
   my $document = $options{"--showdoc"};
   if ($document eq "template") {
      print $tplsequencedoc;
   }
   elsif ($document eq "rules") {
      print $rules;
   }
   elsif ($document eq "vocabulary") {
      print $vocabularies;
   }
   elsif ($document eq "translations") {
      print $translations;
   }
   elsif ($document eq "reportxsd") {
      print $reportxsd;
   }
   elsif ($document eq "classify") {
      print $classify;
   }
   else {
      print ("Document '" . $document . "' not recognised. Must be one of 'template', 'rules', 'vocabulary', 'translations', 'reportxsd' or 'classify'\n\n");
      exit;
   }
   exit;
}
if (exists($options{'--usetemplate'})) {
   $tplsequencedoc = &read_document($options{'--usetemplate'});
}
if (exists($options{'--userules'})) {
   $rules = &read_document($options{'--userules'});
}
if (exists($options{'--usevocabulary'})) {
   $vocabularies = &read_document($options{'--usevocabulary'});
}
if (exists($options{'--usetranslations'})) {
   $translations = &read_document($options{'--usetranslations'});
}
if (exists($options{'--useclassify'})) {
   $classify = &read_document($options{'--useclassify'});
}
if (exists($options{'--force'})) {
   $force_doc = &read_document($options{'--force'});
}
my $filescount = scalar @allfiles;
if (exists($options{'--help'})) {
   print ($usagetext);
   print ($helptext);
   exit;
}
if ($filescount == 0 and ! exists($options{'--documentation'})) {
   print ($usagetext);
   exit;
}
my %allhash = ();
my @allhashkeys = ();
my %templatehash = ();
my %classifyhash = ();
my %force_results = ();
my %force_appends = ();
my %conventions_hash = ();
my @templatearr = ();
my @tplsequence = ();
my @tplcontent = ();
my %coord_vars = ();
my %standard_names = ();
my %elements = ();
my %vocabhash = ();
my %translations = ();
my $notavailable = 'Not available';
#
#  Extract metadata from netCDF files
#  and build the %allhash hash.
#
&read_ncfiles(\@allfiles);
#
#  Build the %classifyhash hash
#
&create_classifyhash();
my $convention = &find_convention();
#
#  Subroutine call: report
#
&report('INFO', "Convention used: " . $convention);
#
#  Build the %elements hash
#
&create_elements_hash();
#
#  Build the %vocabhash hash
#
&create_vocabhash();
#
#  Build the %translations hash
#
&create_translations();
#
#  Build the %force_results hash
#
&create_force_results();
if ($debug eq "allhashkeys") {
   foreach my $key (@allhashkeys) {
      print ($key . "\n");
   }
}
if ($debug eq "allhashvalues") {
   foreach my $key (@allhashkeys) {
      print ($key . "\n");
      print ("    = " . $allhash{$key} . "\n");
   }
}
if ($debug eq "namesarr") {
   my $namesref = &get_list_from_hashkeys('^VAR \S+ SHAPE ', 1);
   foreach my $name (@$namesref) {
      print ($name . "\n");
   }
}
if ($debug eq "elements") {
   foreach my $key (keys %elements) {
      print ($key . ': ' . $elements{$key} . "\n");
   }
   exit;
}
if ($debug eq "classify") {
   foreach my $key (keys %classifyhash) {
      print ($key . ': ' . $classifyhash{$key} . "\n");
   }
   exit;
}
if ($debug eq "splitexact") {
   my $test1 = 'En&xyz;To';
   my $ref = &splitexact($test1, '&xyz;');
   &printarray($ref);
   exit;
}
if ($debug eq "templatearr") {
#   
#     Subroutine call: printarray
#   
   &printarray(\@templatearr);
   exit;
}
if ($debug eq "force") {
   foreach my $key (keys %force_results) {
      my $text = '';
      if (exists($force_appends{$key})) {
         $text = 'append';
      }
      print ($key . ': ' . $force_results{$key} . " " . $text . "\n");
   }
   exit;
}
#
#  Check variables 
#  and build hashes %coord_vars and %standard_names
#
&check_variables();
if (exists($options{'--showglobatt'})) {
   my $showglobattname = $options{'--showglobatt'};
   my $filesref = &get_list_from_hashkeys('^GATT ' . $showglobattname . ' ', 2);
   my %values = ();
   foreach my $fnum (@$filesref) {
      my $val = $allhash{'GATT ' . $showglobattname . ' ' . $fnum};
      $values{$val} = 1;
   }
   foreach my $key (keys %values) {
      print ($key. "\n");
   }
   exit;
}
if (exists($options{'--listglobatts'})) {
   my $gattref = &get_list_from_hashkeys('^GATT ',1);
   my %gatthash = ();
   foreach my $gatt (@$gattref) {
      $gatthash{$gatt} = 1;
   }
   foreach my $key (keys %gatthash) {
      print ($key . "\n");
   }
   exit;
}
#
#  Read the template document
#  and construct the @tplsequence and @tplcontent arrays
#
&construct_tpl();
if ($debug eq "showtpl") {
#   
#    foreach value in an array
#   
   foreach my $fields (@tplsequence) {
      print ($fields . "\n");
   }
   print ("----------------------\n\n");
   for (my $ix=0; $ix < scalar @tplcontent; $ix++) {
      print (sprintf ('%3d',$ix) . ': ' . $tplcontent[$ix] . "\n\n");
   }
   exit;
}
&check_mandatory();
if (! exists($options{'--documentation'})) {
#   
#     Create the MMD xml file
#   
   &create_mmd_xml();
#   
#     Create XML report and exit
#   
   &report_and_exit();
}
#
# Subroutines
# -----------
#
#
#  Sub read_ncfiles
#
$programdoc{"read_ncfiles"} = <<'EOF';

The read_ncfiles subroutine builds the 'allhash' hash and the 'allhashkeys' array containing all the keys in 'allhash'
in lexical order.

The 'allhash' hash collects all information about all the files/URLs given on the command line. For files, the 'ncdump -h'
command is used to extract the information. For URLs, a DAS document retrieved from the internet is used.

The key - value pairs of the 'allhash' hash have the following content:

KEYS                                                     VALUE

"DIM " . $name . " " . $filenumber                       Length of the dimension with name $name
"GATT " . $name . " " . $filenumber                      Value of global attribute $name
"VAR " . $var . " ATT " . $name . " " . $filenumber      Value of variable attribute $name for variable $var
"VAR " . $var . " TYPE " . $filenumber                   Type of variable $var (int, float, etc.)
"VAR " . $var . " SHAPE " . $filenumber                  Shape of variable $var. A shape lists the dimensions
                                                         used by the variable. Example: "time yc xc"

The $filenumber's are numbers starting from 0 for the first file given on the command line (or found in the itemlist file).
For each additional file the filenumber increases by 1.

EOF
   sub read_ncfiles {
      my ($filesref) = @_;
      my $filenumber = 0;
      foreach my $file (@$filesref) {
#         
#           Check if "file" is an URL:
#         
         if ($file =~ /^https?:\/\//) {
#            
#              If the URL ends in .html, substitute to .das:
#            
            if ($file =~ /^(.*)\.html$/) {
               $file = $1 . '.das';
            }
#            
#              Only accept .das URLs:
#            
            if ($file =~ /\.das$/) {
               $item_type = "das";
               my $dasscript = $getdasscript;
#               
#                 Substitute all occurences of a match:
#               
               $dasscript =~ s/==URL==/$file/mg;
#               
#                 Open file for writing
#               
               open (DAS,">/tmp/das_script.sh");
                  print DAS $dasscript;
               close (DAS);
#               
#                 Run command and collect output
#               
               my $result = `chmod +x /tmp/das_script.sh; /tmp/das_script.sh 2>&1`;
               if ($? != 0) {
                  &report("ERROR", "Getting DAS document from the following URL failed: '" . $file . "'");
                  $result = `rm -f /tmp/das_document 2>&1`;
                  $result = `rm -f /tmp/das_script.sh 2>&1`;
                  &report_and_exit();
               }
               my $dascontent1 = &read_document('/tmp/das_document');
               $result = `rm -f /tmp/das_document 2>&1`;
               $result = `rm -f /tmp/das_script.sh 2>&1`;
#               
#                 Convert to UTF-8
#               
               my $dascontent = decode("iso-8859-1", $dascontent1);
               $dascontent = encode("utf-8", $dascontent);
#               
#                 Split string using regexp:
#               
               my @dasarray = split(/\n/,$dascontent);
               my $currentvar = "";
               my $prevword = "";
               my $type = "";
               my $ncglobal = 0;
               my $parseglobal = 0;
               my $globatt = "";
               my $globattval = "";
               my $globattrex = "";
               foreach my $line (@dasarray) {
                  while ($line =~ /^\s*(\S+)(.*?)$/) {
                     my $word = $1;
                     $line = $2;
                     if ($word eq "{") {
                        if ($prevword ne "Attributes") {
                           $currentvar = $prevword;
                           $allhash{"VAR " . $currentvar . " SHAPE " . $filenumber} = 1;
                        }
                        if ($prevword eq "NC_GLOBAL") {
                           $ncglobal = 1;
                        }
                     }
                     elsif ($ncglobal == 1) {
                        if ($parseglobal == 0) {
                           if ($word eq "}") {
                              $ncglobal = 0;
                           }
                           else {
                              $type = $word;
                              $parseglobal = 1;
                           }
                        }
                        elsif ($parseglobal == 1) {
                           $globatt = $word;
                           $parseglobal = 2;
                        }
                        elsif ($parseglobal == 2) {
                           $globattval = $word;
#                           
#                             Check if expression matches RE:
#                           
                           if ($globattval =~ /^"(.*)$/) {
                              $globattval = $1; # First matching ()-expression
                              $globattrex = '^(.*)";$';
                           }
                           else {
                              $globattrex = '^(.*);$';
                           }
#                           
#                             Check if expression matches RE:
#                           
                           if ($globattval =~ /$globattrex/) {
                              $globattval = $1; # First matching ()-expression
                              $allhash{"GATT " . $globatt . " " . $filenumber} = $globattval;
                              $parseglobal = 0;
                           }
                           else {
                              $parseglobal = 3;
                           }
#                           
#                             Check if expression matches RE:
#                           
                           if ($line =~ /^\s*$/) {
                              $globattval .= "\n";
                           }
                        }
                        elsif ($parseglobal == 3) {
#                           
#                             Check if expression matches RE:
#                           
                           if ($word =~ /$globattrex/) {
                              $globattval .= " $1"; # First matching ()-expression
                              $allhash{"GATT " . $globatt . " " . $filenumber} = $globattval;
                              $parseglobal = 0;
                           }
                           else {
                              $globattval .= " $word";
#                              
#                                Check if expression matches RE:
#                              
                              if ($line =~ /^\s*$/) {
                                 $globattval .= "\n";
                              }
                           }
                        }
                     }
                     elsif ($prevword ne "") {
                        if ($word eq "standard_name") {
                           $type = $prevword;
                        }
                        if ($prevword eq "standard_name") {
#                           
#                             Check if expression matches RE:
#                           
                           if ($word =~ /^"([^"]*)";$/) {
                              my $value = $1; # First matching ()-expression
                              $allhash{"VAR " . $currentvar . " ATT standard_name " . $filenumber} = $value;
                           }
                        }
                     }
                     $prevword = $word;
                  }
               }
            }
         }
         else {
            my @xmlcontent;
            if (exists($options{'--ncdumpx'})) {
#               
#                 Run the ncdump command
#                 and collect the output lines to elements in array @xmlcontent
#               
               @xmlcontent = `$ncdumpbin -x $file 2>&1`;
            }
            else {
#               
#                 Run the ncdump command
#                 and collect the output lines to elements in array @xmlcontent
#               
               @xmlcontent = `$ncdumpbin -h $file 2>&1`;
            }
            my $currentvar = "";
            my $attname = "";
            my $endchar = "";
            if (! exists($options{'--ncdumpx'})) {
               my $part = "NONE";
               foreach my $linex (@xmlcontent) {
                  my $line = decode("iso-8859-1", $linex);
                  $line = encode("utf-8", $line);
#                  
#                    Check if expression matches RE:
#                  
                  if ($line =~ /^dimensions:/) {
                     $part = "DIM";
                  }
                  elsif ($line =~ /^variables/) {
                     $part = "VAR";
                  }
                  elsif ($line =~ /^\/\/ global attributes:/) {
                     $part = "GLOB";
                  }
                  else {
                     if ($part eq "DIM") {
#                        
#                          Check if expression matches RE:
#                        
                        if ($line =~ /^\s*(\w+)\s*=\s*(\w+)\s*;/) {
                           my $name = $1; # First matching ()-expression
                           my $length = $2;
                           $allhash{"DIM " . $name . " " . $filenumber} = $length;
                        }
                     }
                     elsif ($part eq "VAR") {
#                        
#                          Check if expression matches RE:
#                        
                        if ($line =~ /^\s*(\w+)\s+(\w+)\b.*;/) {
                           my $type = $1; # First matching ()-expression
                           my $varname = $2;
                           $allhash{"VAR " . $varname . " TYPE " . $filenumber} = $type;
                        }
#                        
#                          Check if expression matches RE:
#                        
                        if ($line =~ /^\s*\w+\s+(\w+)\(([^)]*)\)\s*;/) {
                           my $varname = $1; # First matching ()-expression
                           my $shape = $2;
#                           
#                             Substitute all occurences of a match:
#                           
                           $shape =~ s/,/ /mg;
                           $shape =~ s/  +/ /mg;
                           $allhash{"VAR " . $varname . " SHAPE " . $filenumber} = $shape;
                        }
#                        
#                          Check if expression matches RE:
#                        
                        if ($line =~ /^\s*(\w+):(\w+)\s*=\s*"([^"]*)"\s*;/) {
                           my $varname = $1; # First matching ()-expression
                           my $attnm = $2;
                           my $attvalue = $3;
                           $allhash{"VAR " . $varname . " ATT " . $attnm . " " . $filenumber} = $attvalue;
                        }
                     }
                     elsif ($part eq "GLOB") {
#                        
#                          Check if expression matches RE:
#                        
                        if ($line =~ /^\s*:(\w+)\s*=\s*"([^"]*)"\s*([;,])/) {
                           $attname = $1; # First matching ()-expression
                           my $attvalue = $2;
                           $endchar = $3;
                           $allhash{"GATT " . $attname . " " . $filenumber} = $attvalue;
                        }
#                        
#                          Check if expression matches RE:
#                        
                        if ($line =~ /^\s*:(\w+)\s*=\s*([a-zA-Z0-9.-]*)\s*([;,])/) {
                           $attname = $1; # First matching ()-expression
                           my $attvalue = $2;
                           $endchar = $3;
                           $allhash{"GATT " . $attname . " " . $filenumber} = $attvalue;
                        }
#                        
#                          Check if expression matches RE:
#                        
                        if ($line =~ /^\s*"([^"]*)"\s*([;,])/) {
                           my $attvalue = $1; # First matching ()-expression
                           $endchar = $2;
                           $allhash{"GATT " . $attname . " " . $filenumber} .= $attvalue;
                        }
                     }
                  }
               }
            }
            else {
               foreach my $linex (@xmlcontent) {
                  my $line = decode("iso-8859-1", $linex);
                  $line = encode("utf-8", $line);
                  if ($line =~ /^\s*<dimension name="(\w+)" length="(\d+)"/) {
                     my $name = $1; # First matching ()-expression
                     my $length = $2;
                     $allhash{"DIM " . $name . " " . $filenumber} = $length;
                  }
                  if ($line =~ /^\s*<attribute name="(\w+)" .*\bvalue="([^"]*)"/) {
                     my $name = $1; # First matching ()-expression
                     my $value = $2;
                     if ($currentvar eq "") {
                        $allhash{"GATT " . $name . " " . $filenumber} = $value;
                     }
                     else {
                        $allhash{"VAR " . $currentvar . " ATT " . $name . " " . $filenumber} = $value;
                     }
                  }
                  if ($line =~ /^\s*<variable name="(\w+)".*type="(\w+)"/) {
                     my $name = $1; # First matching ()-expression
                     my $type = $2;
                     $currentvar = $name;
                     $allhash{"VAR " . $name . " TYPE " . $filenumber} = $type;
                  }
                  if ($line =~ /^\s*<variable name="(\w+)" shape="([^"]*)"/) {
                     my $name = $1; # First matching ()-expression
                     my $shape = $2;
                     $allhash{"VAR " . $name . " SHAPE " . $filenumber} = $shape;
                  }
               }
            }
         }
         $filenumber++;
      }
#      
#        Sort hash keys in lexical order:
#      
      @allhashkeys = sort {$a cmp $b} keys(%allhash);
   }
#
# Sub check_variables
#
$programdoc{"check_variables"} = <<'EOF';

The check_variables routine checks variables in the netCDF files. 
Gives warning if variables with the same name (but from different files) have different 
shapes (i.e. differ in number and sequence of dimentions).
Also checks that all array variables are present in all files.

Builds the %coord_vars hash. For all coordinate variables found, $coord_vars{VARNAME} is set to 1,
where VARNAME is the name of the coordinate variable. There are two kind of coordinate variables:
Those having a dimention (shape) equal to the variable name, and those declared as coordinate
variables through use of the 'coordinates' variable attribute.

Builds the %standard_names hash. For all standard_names found, $standard_names{STDNAME} is set to 1,
where STDNAME is the standard name.

EOF
sub check_variables {
#   
#    Get list of all array variables
#   
   my $namesref = &get_list_from_hashkeys('^VAR \S+ SHAPE ', 1);
   foreach my $name (@$namesref) {
      my $rex = '^VAR ' . $name . ' SHAPE';
      my $filesref = &get_list_from_hashkeys($rex, 3);
      if (scalar @$filesref != $filescount) {
         &report("WARNING", "Array variable " . $name . " is not present in all files");
      }
      my %shapes = ();
      foreach my $filenum (@$filesref) {
         my $shape = $allhash{"VAR " . $name . " SHAPE " . $filenum};
         if ($shape eq $name) {
            $coord_vars{$name} = 1;
         }
         $shapes{$shape} = 1;
      }
      if (scalar (keys %shapes) != 1) {
         &report("WARNING", "Array variable " . $name . " has not the same shape in all files");
      }
      $rex = '^VAR ' . $name . ' ATT standard_name';
      $filesref = &get_list_from_hashkeys($rex, 4);
      if (@$filesref > 0) {
         my $fnum = $filesref->[0];
         my $stname = $allhash{'VAR ' . $name . ' ATT standard_name ' . $fnum};
         $standard_names{$stname} = 1;
      }
   }
   if ($debug eq "standard_names") {
      my $text = join(" ",keys %standard_names);
      print ("Standard names: " . $text . "\n");
   }
#   
#    Find coordinate variables
#    based on the values of the coordinates attribute
#   
   foreach my $name (@$namesref) {
      if (! exists($coord_vars{$name})) {
         my $filesref = &get_list_from_hashkeys('^VAR ' . $name . ' ATT coordinates', 4);
         if (@$filesref > 0) {
            my $fnum = $filesref->[0];
            my $coords = $allhash{'VAR ' . $name . ' ATT coordinates ' . $fnum};
            foreach my $coord (split(/\s+/,$coords)) {
               $coord_vars{$coord} = 1;
            }
         }
      }
   }
   if ($debug eq "coord_vars") {
      my $text = join(" ",keys %coord_vars);
      print ("Coordinate variables: " . $text . "\n");
   }
}
#
#  Sub create_elements_hash
#
$programdoc{"create_elements_hash"} = <<'EOF';

 Read the rules document and build the %elements hash.

 Each key in this hash is the elementnames field in a rule from the rules document. The value
 is the corresponding use-clause (without the 'use' keyword).

EOF
sub create_elements_hash {
   my @rules_arr = split(/\n/,$rules);
   my $name = "";
   foreach my $line (@rules_arr) {
      if ($line =~ /^#/) {
#       If comment line, ignore
      }
      elsif ($line =~ /^element (.*) use\b(.*)$/) {
         $name = $1; # First matching ()-expression
         my $rest = $2;
         $elements{$name} = $rest;
      }
      else {
         if ($line =~ /^\s*(.+)\s*$/) {
            my $stripped = $1; # First matching ()-expression
            $elements{$name} .= ' ' . $stripped;
         }
      }
   }
   foreach my $name1 (keys %elements) {
      $elements{$name1} =~ s/^\s*//mg;
   }
}
#
# Sub construct_tpl
#
$programdoc{"construct_tpl"} = <<'EOF';

  Constructs two arrays, tplsequence and tplcontent based on the content of the template (tplsequencedoc) document.

  The template document contains a sequence of templates. Each template comprise a set of contigous lines. This is
  an example of a template:

=geographic_extent 1 3 M:2
1  <mmd:geographic_extent> M
2    <mmd:rectangle> M
2      <mmd:north>==north==</mmd:north> M
2      <mmd:south>==south==</mmd:south> M
2      <mmd:east>==east==</mmd:east> M
2      <mmd:west>==west==</mmd:west> M
2    </mmd:rectangle> M
3  </mmd:geographic_extent> M
 
  The tplsequence array contains one entry for each of these templates. Each entry comprise four blank-separated fields: 
 
  NAME BEGIN END LIST
 
  The NAME field is the name of the template, the word just behind the '=' character in the first line of the template.
  The last three fields may contain indices into the tplcontent array. BEGIN and END may each contain a single index, while LIST
  contains a list of entities separated by '-'. Each of these entities comprise two fields separated by ':', like this:
  CODE:INDEX.
 
  Examples of two tplsequence entries:
 
     geographic_extent 24 57 M:63
     abstract 142 251 M:302-OR:129 
 
  The BEGIN and END fields may alternatively contain the text "empty".
 
  The tplcontent array contains linegroups. A linegroup is a contiguous sequence of lines taken from a
  template. The lines in one linegroup have the same digit in the first character position. The 'geographic_extent'
  template shown above contains three linegroups, identified by digits 1, 2 and 3 respectively.

  The linegroups are stripped of the initial digit when copied into the tplcontent array. The linegroups in the tplcontent
  array are identified by the index position they have in the array. These indices are used in the tplsequence array to
  reference the linegroups. For example, inside the 'geographic_extent' template as found in the template document, the
  numbers 1, 2 and 3 in the first line in the template refers to the corresponding linegroups in the template. These
  "local" references are substituted with indices into the tplcontent array when entries in the tplsequence array are
  created.

  The actual building of the two arrays (tplsequence and tplcontent) are done inside sub update_tpl.
 
  The CODEs in the LIST field of a tplsequence entry has the following meaning:
 
  M   - The corresponding linegroup is mandatory, but not repeatable 
  MR  - The linegroup is mandatory and can be repeated
  O   - The linegroup is optional, but not repeatable
  OR  - The linegroup is optional and repeatable

EOF
sub construct_tpl {
   my @templates_arr = split(/\n/,$tplsequencedoc);
   my $key = "";
   my $fields = "";
   my $newstuff = 0;
   my $index = 0;
   my %conthash = ();
   foreach my $line (@templates_arr) {
      if ($line =~ /^#/) {
#       If comment line, ignore
      }
      elsif ($line =~ /^=(\S+)\s+(.+)$/) {
         my $key1 = $1;
         my $fields1 = $2;
         if ($newstuff) {
            $index = &update_tpl($index, \%conthash, $key, $fields);
            $newstuff = 0;
         }
         $key = $key1;
         $fields = $fields1;
         %conthash = ();
      }
      else {
         if ($line =~ /^(\d+)\b(.*)$/) {
            my $numid = $1;
            my $rest = $2;
            if ($rest =~ /^\s(.*)$/) {
               $rest = $1; # First matching ()-expression
            }
            if (exists($conthash{$numid})) {
               $conthash{$numid} .= $rest . "\n";
            }
            else {
               $conthash{$numid} = $rest . "\n";
            }
         }
         else {
            &report("ERROR", "Unexpected line in template document: '" . $line . "'");
            &report_and_exit();
         }
         $newstuff = 1;
      }
   }
   if ($newstuff) {
      $index = &update_tpl($index, \%conthash, $key, $fields);
   }
}
#
# Sub update_tpl
#
$programdoc{"update_tpl"} = <<'EOF';

  Build the tplsequence and the tplcontent arrays.

  This routine is called from sub contruct_tpl, and must be understood within that context.
  Update_tpl takes four arguments:

  index        - The current index in the tplcontent array. One or more new linegroups in the tplcontent array will be created
                 from this index position and on.
  conthashref  - Reference to the conthash hash containing linegroups identified by "local" digits in the templates.
  key          - Template name (e.g. "geographic_extent")
  fields       - The rest of the first line of the template, after the template name (e.g. "1 3 M:2")

  The tplcontent array will be updated with the linegroups found in the conthash hash. Each linegroup will occupy one
  entry in the array from index position 'index' and on. The 'index' variable will be updated to represent the next
  free entry in the tplcontent array, and returned to the calling routine.

  A new entry in the tplsequence array will be created and pushed to the end of the array. This entry will contain the 
  template name (key), a space character and the content of the fields argument. Before this fields content is added
  to the entry, all "local" digits identifying linegroups are substituted with the corresponding index positions within
  the tplcontent array. 

EOF
sub update_tpl {
   my ($index,$conthashref,$key,$fields) = @_;
#   
#     Sort hash keys in lexical order:
#   
   my @hkeys = sort {$a cmp $b} keys(%$conthashref);
   foreach my $numid (@hkeys) {
      $tplcontent[$index] = $conthashref->{$numid};
      chomp($tplcontent[$index]);
      $fields =~ s/\b$numid\b/$index/g;
      $index++;
   }
   push (@tplsequence,$key . ' ' . $fields);
   return $index;
}
#
# Sub create_vocabhash
#
$programdoc{"create_vocabhash"} = <<'EOF';

Creates the vocabhash hash based on the vocabulary document.

The vocabulary document contains one or more vocabularies, each identfied by a vocabulary name. Each vocabulary has one or
more members. For each vocabulary member, a key is constructed in the vocabhash containing the corresponding vocabulary name
and a lovercase version of the member, separated by a space character. The value corresponding to this key is the original 
version of the member (i.e. not the lovercase version).

The purpose of this hash is to compare metadata that has to obey a vocabulary, with the members of that vocabulary.
The comparision is done using the lovercase version of both metadata and members, and if they agree, the metadata value
is accepted. Hovever, the correct member value (no lovercase) is used in the resulting XML document. This way, upper/lovercase
errors frequently occuring in the harvested metadata, are automatically corrected.

EOF
sub create_vocabhash {
   my @vocab_arr = split(/\n/,$vocabularies);
   my $name;
   foreach my $line (@vocab_arr) {
      if ($line =~ /^#/) {
#       If comment line, ignore
      }
      elsif ($line =~ /^(\w+)/) {
         $name = $1; # First matching ()-expression
      }
      elsif ($line =~ /^\s+\b(.+)\b\s*$/) {
         my $value = $1; # First matching ()-expression
#         
#           Convert to lowercase 
#         
         my $val1 = lc($value);
         if (defined($name)) {
            $vocabhash{$name . ' ' . $val1} = $value;
         }
         else {
            &report("ERROR", "First line in the vocabulary document starts with a space.");
            &report_and_exit();
         }
      }
      else {
         &report("ERROR", "Unexpected line in the vocabulary document: " . $line);
         &report_and_exit();
      }
   }
}
#
# Sub create_translations
#
$programdoc{"create_translations"} = <<'EOF';

Creates the translations hash based on the translations document.

The translations document contains one or more translation tables, each identfied by a name. Each translation table has one or
more rows, each containing an original metadata value and a translated value. For each row, a key is constructed in the 
translations hash containing the corresponding table name and a lovercase version of the original metadata value, separated 
by "->". The value corresponding to this key is the translated value.

The purpose of this hash is to translate metadata obeying a metadata standard different from MMD, to the MMD standard.
Any uppercase/lovercase differences between the harvested metadata and the original metadata found in the tables, will 
be ignored.

EOF

sub create_translations {
   my @translate_arr = split(/\n/,$translations);
   my $name;
   foreach my $line (@translate_arr) {
      if ($line =~ /^#/) {
#       If comment line, ignore
      }
      elsif ($line =~ /^(\w+)/) {
         $name = $1; # First matching ()-expression
      }
      elsif ($line =~ /^\s+\b(.+)\b\s*->\s*\b(.+)\b\s*$/) {
         my $value = $1; # First matching ()-expression
         my $translatedto = $2; # First matching ()-expression
#         
#           Convert to lowercase 
#         
         my $val1 = lc($value);
         if (defined($name)) {
            $translations{$name . ' ' . $val1} = $translatedto;
         }
         else {
            &report("ERROR", "First line in the translations document starts with a space.");
            &report_and_exit();
         }
      }
      else {
         &report("ERROR", "Unexpected line in the translations document: " . $line);
         &report_and_exit();
      }
   }
}
#
# Sub create_force_results
#
$programdoc{"create_force_results"} = <<'EOF';

Builds the force_results hash if a force document is provided by the --force option.

The force document contains metadata that the user want to force into the resulting MMD xml. The document contain
two types of lines:

names = value
names .= value

Each line may eventually be followed by continuation lines without "=" characters. The continuation lines are considered
part of the value, and are concatenated to the value as found in the first line. Newlines (\n) are used to separate each
added line within the value.

The 'names' are the elementnames found in one of the rules in the rules document.

The first type of line (names = value) will force the given value to be used, irrespective of any metadata that may be
found in the harvested metadata.

If the second type is used (names .= value), the given value is appended to any metadata value(s) found in the harvested
metadata by using the rules document.

EOF
sub create_force_results {
   if ($force_doc ne '') {
      my @force_arr = split(/\n/,$force_doc);
      my $accvalue = "NOT-INITIALIZED";
      my $prevnames = '';
#      
#       foreach value in an array
#      
      foreach my $line (@force_arr) {
         if ($debug eq "force") {
            print "---line=${line}---\n";
         }
         my $names = '';
         my $value = '';
#         
#           Check if expression matches RE:
#         
         if ($line =~ /^\s*([^=]+)=(.*)$/) {
            $names = $1; # First matching ()-expression
            $value = $2;
#            
#              Check if expression matches RE:
#            
            if ($names =~ /^(.*?)\s*\.$/) {
               $names = $1; # First matching ()-expression
               $force_appends{$names} = 1;
               if ($debug eq "force") {
                  print "---force_appends=${names}---\n";
               }
            }
#            
#              Substitute all occurences of a match:
#            
            $names =~ s/\s*$//;
         }
         if ($debug eq "force") {
            print "---names=${names}---value=${value}\n";
         }
         if (exists($elements{$names}) && $names ne '') {
            if ($debug eq "force") {
               print "---Found in elements: $elements{$names}\n";
            }
            if ($accvalue ne "NOT-INITIALIZED") {
               $force_results{$prevnames} = $accvalue;
            }
#            
#              Substitute all occurences of a match:
#            
            $value =~ s/^\s+//;
            $value =~ s/\s+$//;
            $accvalue = $value;
         }
         else {
            if ($accvalue ne "NOT-INITIALIZED") {
               my $val1 = $line;
               $val1 =~ s/^\s*//;
               $val1 =~ s/\s*$//;
               $accvalue .= "\n" . $val1;
            }
            else {
               &report("WARNING", "Force document has an initial line that is not an element name:" . $line);
               &report_and_exit();
            }
         }
         if ($names ne "") {
            $prevnames = $names;
         }
      }
      if ($accvalue ne "NOT-INITIALIZED") {
         $force_results{$prevnames} = $accvalue;
      }
      my $notfound = '';
#      
#       foreach key in a hash
#      
      foreach my $hk (keys %force_results) {
         if (! exists($elements{$hk})) {
            $notfound .= "'" . $hk . "', ";
         }
      }
      if ($notfound ne '') {
         my $length = length($notfound);
         $notfound = substr($notfound,0,$length - 2);
         &report("ERROR", "Force document has 'key = value' lines where the key is not an element name. The following keys are not found: " . $notfound);
         &report_and_exit();
      }
   }
}
#
# Sub create_classifyhash
#
$programdoc{"create_classifyhash"} = <<'EOF';

This routine creates three hashes that are used to decide which metadata convention the harvested metadata most
likely obey:

conventions_hash     - The keys in this hash are convention names. The values are not used.
classifyhash         - The keys in this hash are global attribute names as found in the harvested metadata.
                       The values are lists of convention names that uses the corresponding global attribute.
mandatoryhash        - The keys in this hash are global attribute names as found in the harvested metadata.
                       The values are lists of convention names where these attributes are mandatory.

EOF
sub create_classifyhash {
   my @classify_arr = split(/\n/,$classify);
   my $name;
   my $globatts;
   foreach my $line (@classify_arr) {
      if ($line =~ /^#/) {
#       If comment line, ignore
      }
      else {
#         
#           If line contains the name of a new convention
#         
         if ($line =~ /^(\w+):\s+(.*)\s*$/) {
            $name = $1; # First matching ()-expression
            $globatts = $2;
         }
         elsif ($line =~ /^\s+(.+)\s*$/) {
            $globatts = $1; # First matching ()-expression
         }
         else {
            &report("ERROR", "Unexpected line in classify document: '" . $line . "'");
            &report_and_exit();
         }
         if (defined($name)) {
            if (defined($globatts)) {
               foreach my $gatt (split(/\s+/,$globatts)) {
                  if ($gatt =~ /^(\w+)\(M\)$/) {
                     $gatt = $1; # First matching ()-expression
                     if (exists($mandatoryhash{$gatt})) {
#                        
#                          Check if expression matches RE:
#                        
                        if ($mandatoryhash{$gatt} !~ /$name/) {
                           $mandatoryhash{$gatt} .= " $name";
                        }
                     }
                     else {
                        $mandatoryhash{$gatt} = $name;
                     }
                  }
                  if (exists($classifyhash{$gatt})) {
#                     
#                       Check if expression matches RE:
#                     
                     if ($classifyhash{$gatt} !~ /$name/) {
                        $classifyhash{$gatt} .= " $name";
                     }
                  }
                  else {
                     $classifyhash{$gatt} = $name;
                  }
               }
            }
            else {
               &report("ERROR", "This line in the classify document contains no global attribute: '" . $line . "'");
               &report_and_exit();
            }
            $conventions_hash{$name} = 1;
         }
         else {
            &report("ERROR", "Initial line in classify document contains no convention name: '" . $line . "'");
            &report_and_exit();
         }
      }
   }
}
#
# Sub check_mandatory
#
$programdoc{"check_mandatory"} = <<'EOF';

Checks if any mandatory global attributes are missing (according to the convention this program deems most
likely used by the metadata). A warning is given for each global attribute missing.
 
EOF
sub check_mandatory {
#   
#    foreach key,value pair in a hash
#   
   while (my ($gatt,$convlist) = each(%mandatoryhash)) {
#      
#        Check if expression matches RE:
#      
      if ($convlist =~ /$convention/) {
         my $filesref = &get_list_from_hashkeys('^GATT ' . $gatt . ' ', 2);
         if (@$filesref == 0) {
            &report("WARNING", "Missing mandatory global attribute: " . $gatt);
         }
      }
   }
}
#
# Sub find_convention
#
$programdoc{"find_convention"} = <<'EOF';

This routine counts how many times each harvested global attribute is used. It then computes a score for each 
convention found in the conventions_hash hash. The score is the sum of all global attribute counts for global
attributes used by the convention. The convention with highest score is returned as the probable convention used
by the harvested metadata.

EOF
sub find_convention {
   my $globattsref = &get_list_from_hashkeys('^GATT ', 1);
   if ($debug eq "convention") {
      print ("-------------- globattsref:\n");
      &printarray($globattsref);
   }
   my %matchcounts = ();
   my $convention = "UNKNOWN";
   my $score = 0;
   foreach my $gatt (@$globattsref) {
      if (exists($classifyhash{$gatt})) {
#         
#          foreach value in a list
#         
         foreach my $conv ($classifyhash{$gatt}) {
            if (exists($matchcounts{$conv})) {
               $matchcounts{$conv}++;
            }
            else {
               $matchcounts{$conv} = 1;
            }
         }
      }
   }
   if ($debug eq "convention") {
      print ("-------------- matchcounts:\n");
      while (my ($conv,$score) = each(%matchcounts)) {
         print ($conv . ': ' . $score . "\n");
      }
   }
   foreach my $conv (keys %conventions_hash) {
      if (exists($matchcounts{$conv})) {
         if ($matchcounts{$conv} > $score) {
            $score = $matchcounts{$conv};
            $convention = $conv;
         }
      }
   }
   if ($debug eq "convention") {
      print ("-------------- convention = " . $convention . "\n");
   }
   return $convention;
}
#
# Sub create_mmd_xml
#
$programdoc{"create_mmd_xml"} = <<'EOF';

Create and output the MMD xml file based on the @tplsequence and @tplcontent arrays described in the construct_tpl
subroutine.

For each entry in the @tplsequence array, the following variables are set:

  $templatename  - The template name; the word just after '=' in the template document.

  $begin         - Index into the tplcontent array for the initial line group

  $beginrepcode  - Repetition code for the initial line group (M, MR, O or OR)

  $end           - Index into the tplcontent array for the final line group

  $endrepcode    - Repetition code for the final line group (M, MR, O or OR)

  $list          - A list of pairs, repcode:index, separated by '-'. Each pair represents a line group where index
                   represents the index into the @tplcontent array where the line group is stored.

From the $list value, the following arrays are set:

  @repcodes      - The repcodes taken from the $list value

  @tplbases      - The line groups corresponding to each pair in the $list value

The %elements hash (built from the rules document) are searched for all rules corresponding to the $templatename
(i. e. the name of the rule must start with the templatename and a space character).

EOF
sub create_mmd_xml {
#   
#    Initialize $mmdxml as an empty string.
#    This variable will at the end of this routine contain the whole MMD xml document.
#    
   my $mmdxml = "";
   if ($debug eq "createmmd") {
      print ("--- Start create_mmd_xml\n");
   }
#   
#    Loop running through each template
#    in the template document.
#   
   foreach my $key_fields (@tplsequence) {
#       E.g key_fields: geographic_extent 13 15 M:14
#                       metadata_status empty empty M:4
      if ($debug eq "createmmd") {
         print ("------ key fields: $key_fields\n");
      }
      my $templatename;
      my $begin;
      my $beginrepcode;
      my $end;
      my $endrepcode;
      my $list;
#      
#        Extract the fields from $key_fields
#      
      if ($key_fields =~ /^(\S+)\s+(\w+)\s+(\w+)\s+\b(.+)\b\s*$/) {
         $templatename = $1;
         $begin = $2;
         $end = $3;
         $list = $4;
      }
      if (! defined($begin)) {
         &report("ERROR", "Wrong template line format: " . $key_fields);
         &report_and_exit();
      }
      if ($begin eq "empty") {
         $begin = "";
         $beginrepcode = "";
      }
      else {
         $begin = $tplcontent[$begin];
         if ($begin =~ /^(.+)\b(M|MR|O|OR)$/) {
            $begin = $1;
            $beginrepcode = $2;
            $begin =~ s/\s*$//;
         }
         else {
            &report("ERROR", "Wrong template line format: " . $begin);
            &report_and_exit();
         }
      }
      if (! defined($end)) {
         &report("ERROR", "Wrong template line format: " . $key_fields);
         &report_and_exit();
      }
      if ($end eq "empty") {
         $end = "";
         $endrepcode = "";
      }
      else {
         $end = $tplcontent[$end];
         if ($end =~ /^(.+)\b(M|MR|O|OR)$/) {
            $end = $1;
            $endrepcode = $2;
            $end =~ s/\s*$//;
         }
         else {
            &report("ERROR", "Wrong template line format: " . $end);
            &report_and_exit();
         }
      }
      if ($beginrepcode ne $endrepcode) {
         &report("ERROR", "Repcodes for begin and end not equal: " . $beginrepcode . ' != ' . $endrepcode);
         &report_and_exit();
      }
      my @lg1 = split(/-/,$list);
      my @repcodes = ();
      my @tplbases = ();
      foreach my $lg (@lg1) {
         my ($repcode,$ix) = split(/:/,$lg);
         push (@repcodes,$repcode);
         push (@tplbases,$tplcontent[$ix]);
      }
      my $found = 0;
      my $rex = '^' . $templatename . '\b';
      $rex =~ s/\./\\./g;
      my $template = "";
      my %ruleresults = ();
      my %rrindices = ();
      my %rrcounts = ();
#      
#       For each elementname
#       in the rules document corresponding to the templatename
#      
#       If several rules correspond to the template name, they will differ in the last key in the elementsname part of the
#       rule (see the rules document). The $lastkey variable is set to this key. The following hashes are set using the
#       $lastkey as key:
#      
#       %rulesresult
#      
      foreach my $hkey (grep {/$rex/} keys %elements) {
         if ($debug eq "createmmd") {
            print ("------ hkey: $hkey\n");
         }
         my $lastkey = $hkey;            # E.g hkey: temporal_extent end_date
         $lastkey =~ s/^.*\b(\w+)$/$1/;     # E.g lastkey: end_date
         if ($debug eq "createmmd") {
            print ("------ lastkey: $lastkey\n");
         }
         if (exists($ruleresults{$lastkey})) {
            &report("ERROR", "Multiple match on last word in elements hash: " . $hkey);
            &report_and_exit();
         }
         else {
            my $rrarr;
            if (exists($force_results{$hkey}) && ! exists($force_appends{$hkey})) {
               $rrarr = [$force_results{$hkey}];
            }
            else {
               $rrarr = &apply_rule($elements{$hkey});
            }
            my @rmodified = ();
            if (scalar @$rrarr > 0) {
               if (exists($force_results{$hkey})) {
                  if (exists($force_appends{$hkey})) {
                     if (scalar @$rrarr > 1) {
#                        
#                          Push values to end of array:
#                        
                        push (@$rrarr,$force_results{$hkey});
                     }
                     else {
#                        
#                          Assign to an array through array reference:
#                        
                        $rrarr->[0] .= "\n" . $force_results{$hkey};
                     }
                  }
               }
               my $rex2 = '^' . $lastkey .'\b';
               my @vocabpart = grep(/$rex2/,keys %vocabhash);
               if (scalar @vocabpart > 0) {
#                  
#                   foreach value in an array
#                  
                  foreach my $value (@$rrarr) {
#                     
#                       Convert to lowercase 
#                     
                     my $val1 = lc($value);
                     if (exists($vocabhash{$lastkey . ' ' . $val1})) {
                        push (@rmodified,$vocabhash{$lastkey . ' ' . $val1});
                     }
                     else {
                        &report("WARNING", "Value '" . $value . "' is not present in vocabulary $lastkey");
                     }
                  }
                  $rrarr = \@rmodified;
               }
            }
            else {
               if (exists($force_results{$hkey})) {
#                  
#                    Push values to end of array:
#                  
                  push (@$rrarr,$force_results{$hkey});
               }
               else {
                  if ($debug eq "createmmd") {
                     print ('------ force_result not found ' . $lastkey . "\n");
                  }
               }
            }
            if ($debug eq "createmmd") {
               print ('------ rulesresult ' . $lastkey . "\n");
               &printarray($rrarr);
            }
            $rrindices{$lastkey} = 0;
            $ruleresults{$lastkey} = $rrarr;
            $rrcounts{$lastkey} = scalar @$rrarr;
         }
      }
      for (my $ix1=0; $ix1 < scalar @tplbases; $ix1++) {
         if ($debug eq "createmmd") {
            print ("------ ix1: $ix1\n");
         }
         my $tplbase = $tplbases[$ix1];
         my $repcode = $repcodes[$ix1];
         my $tpl1 = "";
         my $continue = 1;
         my $localfound = 0;
         my $repcount = 0;
         while (++$repcount < 6 && $continue) {
            if ($debug eq "createmmd") {
               print ("--------- continue: $continue repcount: $repcount\n");
            }
            foreach my $line1 (split(/\n/,$tplbase)) {
               if ($debug eq "createmmd") {
                  print ("------------ line1: $line1\n");
               }
               my $line2;
               my $linerepcode;
               if ($line1 =~ /^(.+)\b(M|MR|O|OR|OX)$/) {
                  $line2 = $1;
                  $linerepcode = $2;
                  $line2 =~ s/\s*$//;
               }
               else {
                  &report("ERROR", "Wrong template line format: " . $line1);
                  &report_and_exit();
               }
               my $key2;
               if ($line2 =~ /^.+==(\w+)==.+$/) {
                  $key2 = $1; # First matching ()-expression
                  if ($debug eq "createmmd") {
                     print ("--------------- match key2: $key2\n");
                  }
                  my $rex1 = '==' . $key2 . '==';
                  if (exists($ruleresults{$key2}) and $rrcounts{$key2} > 0) {
                     if ($linerepcode eq "OR" or $linerepcode eq "MR") {
                        my $resultsref = $ruleresults{$key2};
                        foreach my $result (@$resultsref) {
                           my $line3 = $line2;
                           $line3 =~ s/$rex1/$result/mg;
                           $tpl1 .= $line3 . "\n";
                        }
                        $localfound = 1;
                        $rrindices{$key2} = $rrcounts{$key2};
                     }
                     else {
                        if ($rrindices{$key2} < $rrcounts{$key2}) {
                           my $ix1 = $rrindices{$key2};
                           my $result = ($ruleresults{$key2})->[$ix1];
                           $rrindices{$key2} = $rrcounts{$key2};
                           $line2 =~ s/$rex1/$result/mg;
                           $tpl1 .= $line2 . "\n";
                           if ($linerepcode ne "OX") {
                              $localfound = 1;
                           }
                        }
                     }
                  }
                  else {
                     if ($linerepcode eq "M" or $linerepcode eq "MR") {
                        $line2 =~ s/$rex1/$notavailable/mg;
                        $tpl1 .= $line2 . "\n";
                     }
                  }
               }
               else {
                  $tpl1 .= $line2 . "\n";
               }
            }
            $continue = 0;
            if ($repcode eq 'OR' or $repcode eq 'MR') {
               foreach my $key2 (keys %rrindices) {
                  if ($rrindices{$key2} < $rrcounts{$key2}) {
                     $continue = 1;
                  }
               }
            }
         }
         if ($repcount >= 6) {
            &report("ERROR", "Loop does not terminate in sub create_mmd_xml");
            &report_and_exit();
         }
         if ($debug eq "createmmd") {
            print ("--- localfound=$localfound repcode=$repcode beginrepcode=$beginrepcode\n");
            print ("--- tpl1:\n$tpl1\n---\n");
         }
         if ($localfound == 1 or $repcode eq 'M' or $repcode eq 'MR' or $beginrepcode eq 'M' or $beginrepcode eq 'MR') {
            if ($begin ne "") {
               $template .= $begin . "\n";
            }
            if ($localfound == 1 or $repcode eq 'M' or $repcode eq 'MR') {
               $template .= $tpl1;
            }
            if ($begin ne "") {
               $template .= $end . "\n";
            }
         }
      }
      $mmdxml .= $template;
   }
   if (exists($options{'--output'})) {
      open (OUT,">$options{'--output'}");
         print OUT $mmdxml;
      close (OUT);
   }
   else {
      print $mmdxml;
   }
}
#
# Sub apply_rule
#
$programdoc{"apply_rule"} = <<'EOF';

Returns a reference to an array containing all results extracted from the netCDF file, or otherwise defined, by
applying the rule given as argument to this routine. The rule comprise a sequence of use clauses as defined in the rules
document.

Two examples of rules:

  GATT:time_coverage_end:max GATT:stop_date:max EXTRACTDATE
  GATT:gcmd_keywords:all:spliton="NEWLINE"

This routine handles five different use clauses:

  GATT        - Global attribute
  STDNAME     - Standard name
  COLLECTION  - Sets the default collection or one provided by an option to the program
  EXTRACTDATE - Modifies the the result from the last GATT clause. Extracts the date from a datetime value.
  TRANSLATE   - Modifies the the result from the last GATT clause. Use of a translation table.

EOF
sub apply_rule {
   my ($rule) = @_;
   my @resultarr = ();
   my @ruleparts = split(/\s+/,$rule);
   foreach my $rulepart (@ruleparts) {
      my @rpelements = split(/:/,$rulepart);
      my $rpcount = scalar @rpelements;
      if ($rpelements[0] eq "GATT") {
         my $attribute = $rpelements[1];
         if ($debug eq "createmmd") {
            print ('--------- attribute: "' . $attribute . "\"\n");
         }
         my $multivalue = "";
         if ($rpcount > 2) {
            $multivalue = $rpelements[2];
         }
         my $spliton = "";
         my $linebreak = "";
         if ($rpcount > 3) {
            if ($rpelements[3] =~ /^spliton="([^"]+)"$/) {
               $spliton = $1; # First matching ()-expression
               if ($spliton eq "SPACE") {
                  $spliton = " ";
               }
               if ($spliton eq "NEWLINE") {
                  if ($item_type eq "file") {
                     if (exists($options{'--ncdumpx'})) {
                        $spliton = "&#xA;";
                     }
                     else {
                        $spliton = '\n';
                     }
                  }
                  else {
                     $spliton = "\n";
                  }
               }
            }
            elsif ($rpelements[3] =~ /^linebreak="([^"]+)"$/) {
               $linebreak = $1; # First matching ()-expression
            }
         }
         if ($debug eq "createmmd") {
            print ('--------- spliton: "' . $spliton . "\"\n");
            print ('--------- linebreak: ' . $linebreak . "\n");
         }
         my $valuesref = &get_globatt_values($attribute);
         if (scalar @$valuesref > 0) {
            my %valueshash = ();
            foreach my $value (@$valuesref) {
               if (defined($value)) {
                  if ($debug eq "createmmd") {
                     print ('----------- value: "' . $value . "\"\n");
                  }
                  if ($spliton ne "") {
#                     
#                       Function call: splitexact
#                     
                     my $valref = &splitexact($value, $spliton);
#                     
#                      foreach value in an array
#                     
                     foreach my $val1 (@$valref) {
                        $val1 =~ s/^\s*(.*)\s*$/$1/;
                        $valueshash{$val1} = 1;
                     }
                  }
                  elsif ($linebreak ne "") {
#                     
#                       Function call: splitexact
#                     
                     my $valref = &splitexact($value, $linebreak);
#                     
#                       Join the elements of an array using string:
#                     
                     my $val2 = join("\n",@$valref);
                     $valueshash{$val2} = 1;
                  }
                  else {
                     $valueshash{$value} = 1;
                  }
               }
            }
            my $finalvalue = "";
#            
#              Sort hash keys in lexical order:
#            
            my @sortedvalues = sort {$a cmp $b} keys(%valueshash);
            if ($debug eq "createmmd") {
               print ("------$rulepart-------sortedvalues------------\n");
               &printarray (\@sortedvalues);
            }
            if ($multivalue eq "max") {
               my $lastix = (scalar @sortedvalues) - 1;
               $finalvalue = $sortedvalues[$lastix];
            }
            elsif ($multivalue eq "min") {
               $finalvalue = $sortedvalues[0];
            }
            else {
               $finalvalue = $sortedvalues[0];
            }
            if ($multivalue ne "all" and defined($finalvalue)) {
               push (@resultarr,$finalvalue);
            }
            else { # $multivalue == "all"
               foreach my $val2 (@sortedvalues) {
                  if (defined($val2)) {
                     push (@resultarr,$val2);
                  }
               }
            }
         }
      }
      elsif ($rpelements[0] eq "STDNAME") {
#         
#          foreach key in a hash
#         
         foreach my $stdname (keys %standard_names) {
            if ( ! exists($stdname_exceptions{$stdname})) {
#               
#                 Push values to end of array:
#               
               push (@resultarr,$stdname);
            }
         }
      }
      elsif ($rpelements[0] eq "COLLECTION") {
#         
#           Push values to end of array:
#         
         push (@resultarr,$collection);
      }
      elsif ($rpelements[0] eq "EXTRACTDATE") {
         for (my $ix=0; $ix < scalar @resultarr; $ix++) {
#            
#              Substitute all occurences of a match:
#            
            $resultarr[$ix] =~ s/^(\d\d\d\d-\d\d-\d\d).*$/$1/mg;
         }
      }
      elsif ($rpelements[0] eq "TRANSLATE") {
         if ($rpcount < 2) {
            &report("ERROR", "Missing reference to translate table in rule " . $rule);
            &report_and_exit();
         }
         my $tableid = $rpelements[1];
         for (my $ix=0; $ix < scalar @resultarr; $ix++) {
            my $result1 = lc($resultarr[$ix]);
#            
#              Check if key exists in hash
#            
            if (exists($translations{$tableid . ' ' . $result1})) {
               $resultarr[$ix] = $translations{$tableid . ' ' . $result1};
            }
         }
      }
   }
   return \@resultarr;
}
#
#  Sub get_list_from_hashkeys
#
$programdoc{"get_list_from_hashkeys"} = <<'EOF';

The 'get_list_from_hashkeys' routine takes a regular expression and a number (N) as arguments. The regular expression is used
to extract all matching keys from the allhashkeys array into a new array. Each entry in the new array is a sequence of 
blank-separated words. The routine creates a list of the Nth word in each entry (N=0 represents the first word). The list is
sorted and duplicates removed, and finally returned as an array reference.

EOF
   sub get_list_from_hashkeys {
      my ($rex,$wordnum) = @_;
      my @hkeys = grep(/$rex/,@allhashkeys);
      my %names = ();
      foreach my $hk (@hkeys) {
         my @hkarr = split(/\s+/,$hk);
         $names{$hkarr[$wordnum]} = 1;
      }
      my @namesarr = sort (keys %names);
      return \@namesarr;
   }
sub get_globatt_values {
   my ($attribute) = @_;
   my @valuesarr = ();
   my $filesref = &get_list_from_hashkeys('^GATT ' . $attribute,2);
   foreach my $fnum (@$filesref) {
      my $val = $allhash{'GATT ' . $attribute . ' ' . $fnum};
      push (@valuesarr,$val);
   }
   return \@valuesarr;
}
sub splitexact {
   my ($string,$splitter) = @_;
   my @valuesarr = ();
   my $splitterlength = length($splitter);
   my $curstring = $string;
   while (length($curstring) > 0) {
      my $pos = index($curstring,$splitter);
      if ($pos < 0) {
         push (@valuesarr,$curstring);
         $curstring = "";
      }
      else {
         push (@valuesarr,substr($curstring,0,$pos));
         my $length = $splitterlength + $pos;
         substr($curstring,0,$length,"");
      }
   }
   return \@valuesarr;
}
sub printarray {
   my ($ref) = @_;
   foreach my $val (@$ref) {
      if (defined($val)) {
         print ($val . "\n");
      }
   }
}
sub read_document {
   my ($filename) = @_;
#   
#     Slurp in the content of a file
#   
   unless (-r $filename) {die "Can not read from file: $filename\n";}
   open (DOCU,$filename);
   undef $/;
   my $document = <DOCU>;
   $/ = "\n"; 
   close (DOCU);
   return $document;
}
sub report {
#   
#     Split argument array into variables
#   
   my ($type,$text) = @_;
   $messages{$type . " " . $text} = 1;
}
sub report_and_exit {
   my $epochtime = time; 
#   
#     Find current UTC time as string
#     e.g: "Thu Oct 13 04:54:34 1994"
#   
   my $utctime = gmtime . " UTC";
   my $filename = "nc_to_mmd_report_" . $epochtime . $$ . '.xml';
   my $exitvalue = 0;
   my $reporttext = "";
   $reporttext = '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
   $reporttext .= '<report xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"' . "\n";
   $reporttext .= 'xsi:noNamespaceSchemaLocation="http://www.met.no/schema/report">' . "\n";
   $reporttext .= "   <date>" . $utctime . "</date>\n";
   $reporttext .= "   <options>\n";
   foreach my $key (keys %options) {
      if ($options{$key} ne "") {
         $reporttext .= "      <opt>" . $key . '=' . $options{$key} . "</opt>\n";
      }
      else {
         $reporttext .= "      <opt>" . $key . "</opt>\n";
      }
   }
   $reporttext .= "   </options>\n";
   $reporttext .= "   <files>\n";
   my $num = 0;
#   
#    foreach value in an array
#   
   foreach my $file (@allfiles) {
      $reporttext .= '      <file num="' . $num . '">' . $file . '</file>' ."\n";
      $num++;
   }
   $reporttext .= "   </files>\n";
   $reporttext .= "   <messages>\n";
   foreach my $msg (keys %messages) {
#      
#        Check if expression matches RE:
#      
      if ($msg =~ /^(\w+)\s*(.*)$/) {
         my $type = $1; # First matching ()-expression
         my $text = $2;
         $reporttext .= '      <msg type="' . $type . '">' . $text . '</msg>' ."\n";
         if ($type eq "ERROR") {
            $exitvalue = 1;
            print STDERR 'ERROR: ' . $text . "\n";
         }
         if ($type eq "WARNING") {
            print STDERR 'WARNING: ' . $text . "\n";
         }
      }
   }
   $reporttext .= "   </messages>\n";
   $reporttext .= "</report>";
#   
#     Open file for writing
#   
   open (REPORT,">$filename");
      print REPORT $reporttext;
   close (REPORT);
   exit $exitvalue;
}
my $worktext;
if (exists($options{'--documentation'})) {
   print ("\n====== nc_to_mmd.pl DOCUMENTATION =======\n");
}
if (exists($options{'--documentation'})) {
$worktext = <<'EOF';

The purpose of the nc_to_mmd.pl program is to extract metadata fron netCDF files and construct MMD xml files
containing the extracted metadata.
EOF
}
if (exists($options{'--documentation'})) {
   print ($worktext);
   print ($usagetext);
   print ($helptext);
}
if (exists($options{'--documentation'})) {
$worktext = <<'EOF';

======== Documents controlling the program ========

A set of text documents control the metadata extraction and the production of the MMD xml. Default versions of these
documents are part of this program, but the user can provide his/her own versions of the documents as described in the usage 
text above. The following is a summary of the documents involved:

Template document     This document defines the overall structure of the MMD xml that will be produced. The sequence
                      of the main elements are defined, and also the sub-elements for each main element. Markup to define
                      elements as mandatory or optional are included, as well as markup to define elements as repeatable. 
                      Named placeholders for metadata are included. These are used in the Rules document.

Rules document        This document describes how each metadata value are extracted from the netCDF files.

Classify document     This document is used to find which metadata convention is used in a netCDF file.

Vocabulary document   Some metadata are restricted to specific vocabularies. This document contains these vocabularies,
                      so that the user can be warned if extracted metadata values are not found in the vocabulary they
                      should obey.

Translations document Some netCDF files may follow standards that use other vocabularies than MMD. This document offer a
                      possibility to translate metadata using these standards to MMD.

The  default versions of these documents are given below:

EOF
print ($worktext);
}
if (exists($options{'--documentation'})) {
#   
#    foreach value in a list
#   
   foreach my $doc ($tplsequencedoc, $rules, $classify, $vocabularies, $translations) {
      print "\n" . $doc;
   }
}
if (exists($options{'--documentation'})) {
$worktext = <<'EOF';

======== Important variables ========

@allfiles          Array used to collect all netCDF file names or URLs on the command line or found in the itemlist file.

%allhash           The 'allhash' hash collects all information about all the files/URLs given on the command line.
                   See details in the subroutine 'read_ncfiles'.

%elements          Each key in this hash is the elementnames field in a rule from the rules document. The value
                   is the corresponding use-clause (without the 'use' keyword).

%force_results     Hash created from a force document if a force document is provided by the --force option.
                   See details in the 'create_force_results' subroutine.

%standard_names    For all standard_names found, $standard_names{STDNAME} is set to 1, where STDNAME is the standard name.

@tplsequence       Array constructed from the template document. One entry for each of the main elements in the template 
                   document. See details in the 'construct_tpl' subroutine.

@tplcontent        Array constructed from the template document. See details in the 'construct_tpl' subroutine.

%translations      This hash is based on the translations document. See details in the 'create_translations' subroutine.

%vocabhash         This hash is based on the vocabulary document. See details in the 'create_vocamhash' subroutine.


======== Subroutines ========

EOF
print ($worktext);
}
if (exists($options{'--documentation'})) {
#   
#    foreach key,value pair in a hash
#   
   while (my ($sub,$text) = each(%programdoc)) {
      print ("\n=== $sub ===\n");
      print ($text);
   }
}
