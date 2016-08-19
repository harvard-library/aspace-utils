# ASpace EAD Batch Ingest Scripts

These scripts rely on the presence of the [aspace-jsonmodel-from-format plugin](https://github.com/lyrasis/aspace-jsonmodel-from-format) in your instance of ArchivesSpace.
The plugin converts ead xml to json object model, which allows import into archivesspace. These scripts need not run on the same instance as the aspace instance, we use http post calls to the api (http://your.aspaceinstance:8089/..., for instance)

## Prerequisites
- In your (remote or local) instance of aspace, install the aspace-jsonmodel-from-format plugin. Install info at:
[https://github.com/lyrasis/aspace-jsonmodel-from-format](https://github.com/lyrasis/aspace-jsonmodel-from-format)
- Full set of EAD files need to be in a local, accessible directory (specified in config.yml, an example is provided [here](config.yml.example)
- Ruby 2.2+.  This should work fine with MRI, jRuby, or whatever, as long as it supports all the dependencies.
## Installation
- Check out this repository
- Create config.yml file based on config.yml.example
- Install dependencies via Bundler

    ``` shell
    gem install bundler # If not already installed
    cd aspace-utils
    bundle install
    ```

## Running the ingester
To run the ingester, place you EAD files in the directory specified in your config.yml, and then run:

``` shell
bundle exec ingest_aspace.rb
```

If you want to keep an eye on what it's doing, I recommend:

``` shell
watch tail ingestlog.log
```

The ingester populates two log files - ingestlog.log and error_responses

At Harvard, we've been running this under screen to keep this running over long periods of time.

## A sad note on max_concurrency
This script is set up to do concurrent requests, but unfortunately this cannot be recommended at this time, due to what I believe is a race condition with creating Subjects/Agents/other shared fields.

## Analysis script
There's also an "analyze_logs.rb" script provided, which can be used thusly:

```
bundle exec analyze_logs.rb ingestlog.log error_responses > analysis.txt
```

It currently assumes that there is ONE and only ONE set of logs in each of those files - if you want to use the analysis script, you'll need to wipe ingestlog.log and error_responses between runs.

## Notes
- repository ids can be found using the api (http://localhost:8089/repositories, for example); they must be parsed out
- really this should handle its own log rotation, sorry, PRs welcome or I'll get to it eventually.
