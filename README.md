# ASpace EAD Batch Ingest Scripts

Run these scripts to set up ead files for ingest, and run the batch ingest for one or more repositories. 
Unlike the ASpace UI importer, this batch ingester will not quit upon first fail.
These scripts rely on the presence of the aspace-jsonmodel-from-format plugin in your instance of aspace.
The plugin converts ead xml to json object model, which allows import into archivesspace. These scripts need not run on the same instance as the aspace instance, we use http post calls to the api (http://your.aspaceinstance:8089/..., for instance)

## Prerequisites
- In your (remote or local) instance of aspace, install the aspace-jsonmodel-from-format plugin. Install info at:
[https://github.com/lyrasis/aspace-jsonmodel-from-format](https://github.com/lyrasis/aspace-jsonmodel-from-format)
- Full set of EAD files need to be in a local, accessible directory (specified in ingest.properties)
## Getting Started with Ingest Scripts
- Check out scripts from the LTS github: `git clone ssh://USERNAME@rand.hul.harvard.edu/home/git/aspace_utils.git`
- Create ingest.properties file based on ingest.properties.example
- Run ingestsetup.sh to initialize and refresh environment, before each ingest
- Run ingest.sh REPOSITORYCODE REPOSITORYID (found in repos.txt) for ingesting a single repository
- Run ingestall.sh to ingest some or all (uncomment as  needed)

## Notes
- ingestsetup.sh additionally creates and rotates logfiles
- repository ids can be parsed from the json using the api (http://localhost:8089/repositories, for example)
- TO DO: harvestall.sh and ingest.sh could use repos.txt (like ingestsetup.sh), and consider making repos.txt a properties file
- TO DO: use jq (json parser) to parse session key from api call in ingest.sh instead of unix tools
