import pandas as pd


def model(dbt, session):
    dbt.config(
        materialized="table",
        packages=["pandas", "scikit-learn"],
        snowflake_warehouse="TRANSFORM_WH_SNOWPARK",
    )
    from sklearn.preprocessing import MinMaxScaler

    df = dbt.ref("fct_churn_features").to_pandas()
    df.columns = [c.lower() for c in df.columns]

    cols = ["days_since_last_use", "tickets_90d", "avg_daily_mb"]
    scaled = MinMaxScaler().fit_transform(df[cols].fillna(0))
    score = 0.5 * scaled[:, 0] + 0.3 * scaled[:, 1] + 0.2 * (1 - scaled[:, 2])

    out = pd.DataFrame({"subscriber_id": df["subscriber_id"], "churn_score": score})
    return session.create_dataframe(out)
