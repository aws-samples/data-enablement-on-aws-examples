# Data Pipeline 

This section aims to give examples of end-to-end data pipelines on AWS. This allows exploration of data integration methods, as well as examples of implementing these using AWS capabilities. 

## Demos

| Demo | Description | 
| --- | --- | 
| [Zero ETL pipeline to Amazon Redshift and GenAI productivity assistance](./zero-etl/README.md) | This demo shows a pipeline integrating data from a source Amazon Aurora MySQL database to an Amazon Redshift serverless data warehouse using zero ETL integration. This establishes a near real time pipeline sending source, transactional data into an analytical plane. From there, Redshift capabilities can be used to perform analytics and QuickSight can be connected via a VPC connection to support business intelligence applications. |