import sys
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.context import SparkContext
from pyspark.sql import functions as F

# --- Boilerplate ---
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'GLUE_DATABASE', 'CURATED_S3_PATH'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# --- Read from the Data Catalog (populated by the crawler) ---
dyf = glueContext.create_dynamic_frame.from_catalog(
    database=args['GLUE_DATABASE'],
    table_name="orders"
)
df = dyf.toDF()

print("Row count before cleaning:", df.count())

# --- Cleaning step 1: remove exact duplicate rows ---
df = df.dropDuplicates()

# --- Cleaning step 2: drop rows with invalid (negative) quantity ---
df = df.filter(F.col("quantity") >= 0)

# --- Cleaning step 3: handle missing/null amount ---
# Idea: where amount is null, recompute it as quantity * unit_price instead of just dropping the row
df = df.withColumn(
    "amount",
    F.when(F.col("amount").isNull(), F.col("quantity") * F.col("unit_price"))
     .otherwise(F.col("amount"))
)

# --- Cleaning step 4: handle missing email ---
# Think about this one: is dropping the row the right call, or filling a placeholder?
df = df.withColumn(
    "email",
    F.when(F.col("email").isNull(), "No Email").otherwise(F.col("email"))
)

print("Row count after cleaning:", df.count())

# --- Convert back to DynamicFrame and write to curated bucket as Parquet ---
cleaned_dyf = DynamicFrame.fromDF(df, glueContext, "cleaned_dyf")

glueContext.write_dynamic_frame.from_options(
    frame=cleaned_dyf,
    connection_type="s3",
    connection_options={"path": args['CURATED_S3_PATH']},
    format="parquet"
)

job.commit()