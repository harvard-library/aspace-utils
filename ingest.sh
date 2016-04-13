#!/bin/bash

# This script ingests EAD into asspace

# usage
if [ $# -ne 2 ]
then
/bin/echo "Usage: `basename $0` repositorycode repositoryid"
echo "Example: `basename $0` ajp 13"
exit 1
fi

REPOSITORYCODE=$1
REPOSITORYID=$2

#read the properties
. ./ingest.properties

EADJSONDIR=$INGESTDIR/$EADJSONDIRNAME

#for now read code and id as args, could use only reposcode 
#and pull id from repos.txt

#should use jq instead, but just cutting the sesion key from the json for now

export TOKEN=$(curl -s -Fpassword=$ADMIN $BACKENDURL/users/admin/login | cut -d '"' -f 4)
#echo "$TOKEN"
echo `date` "ingesting $REPOSITORYCODE ead"

REPOSITORYDIR=$INGESTDIR/$REPOSITORYCODE
#echo "$REPOSITORYDIR"
files="$REPOSITORYDIR/*.xml"
for f in $files
do
	#get the eadid (strip of the .xml suffix)
	FILENAME=`basename $f|cut -c1-8`
	# get the jsonmodel representation of xml, write <eadid>.json to disc
	echo "converting $FILENAME xml to json"
	curl -s -H "Content-Type: text/xml" -H "X-ArchivesSpace-Session: $TOKEN" -X POST -d @"$f" "$BACKENDURL/plugins/jsonmodel_from_format/resource/ead" > $EADJSONDIR/$FILENAME.json

	# import it by sending it to the batch_imports endpoint
	echo "posting $FILENAME json to archivesspace"
	curl -s -H "Content-Type: application/json" -H "X-ArchivesSpace-Session: $TOKEN" -X POST -d @"$EADJSONDIR/$FILENAME.json" "$BACKENDURL/repositories/$REPOSITORYID/batch_imports" 

done
