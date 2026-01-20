

-- =====================================
-- Set Database & Schema Context
-- =====================================
CREATE DATABASE IF NOT EXISTS HOTEL_DB;
USE DATABASE HOTEL_DB;
USE SCHEMA PUBLIC;

-- =====================================
-- Create File Format
-- =====================================
CREATE OR REPLACE FILE FORMAT FF_CSV
    TYPE = 'CSV'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    SKIP_HEADER = 1
    NULL_IF = ('NULL', 'null', '');

-- =====================================
-- Create Stage
-- =====================================
CREATE OR REPLACE STAGE STG_HOTEL_BOOKINGS
    FILE_FORMAT = (FORMAT_NAME = FF_CSV);

-- =====================================
-- Create Bronze Table
-- =====================================
CREATE OR REPLACE TABLE BRONZE_HOTEL_BOOKING (
    booking_id STRING,
    hotel_id STRING,
    hotel_city STRING,
    customer_id STRING,
    customer_name STRING,
    customer_email STRING,
    check_in_date STRING,
    check_out_date STRING,
    room_type STRING,
    num_guests STRING,
    total_amount STRING,
    currency STRING,
    booking_status STRING
);

-- =====================================
-- Load Data into Bronze Table
-- =====================================
COPY INTO BRONZE_HOTEL_BOOKING
FROM @STG_HOTEL_BOOKINGS
FILE_FORMAT = (FORMAT_NAME = FF_CSV)
ON_ERROR = 'CONTINUE';

-- =====================================
-- Preview Bronze Data
-- =====================================
SELECT * 
FROM BRONZE_HOTEL_BOOKING 
LIMIT 50;

-- =====================================
-- Create Silver Table
-- =====================================
CREATE OR REPLACE TABLE SILVER_HOTEL_BOOKINGS (
    booking_id VARCHAR,
    hotel_id VARCHAR,
    hotel_city VARCHAR,
    customer_id VARCHAR,
    customer_name VARCHAR,
    customer_email VARCHAR,
    check_in_date DATE,
    check_out_date DATE,
    room_type VARCHAR,
    num_guests INTEGER,
    total_amount FLOAT,
    currency VARCHAR,
    booking_status VARCHAR
);

-- =====================================
-- Data Quality Checks (Optional)
-- =====================================
-- Invalid emails
SELECT customer_email
FROM BRONZE_HOTEL_BOOKING
WHERE customer_email IS NULL
   OR NOT (customer_email LIKE '%@%.%');

-- Negative amounts
SELECT total_amount
FROM BRONZE_HOTEL_BOOKING
WHERE TRY_TO_NUMBER(total_amount) < 0;

-- Invalid date ranges
SELECT check_in_date, check_out_date
FROM BRONZE_HOTEL_BOOKING
WHERE TRY_TO_DATE(check_out_date) < TRY_TO_DATE(check_in_date);

-- Booking status values
SELECT DISTINCT booking_status
FROM BRONZE_HOTEL_BOOKING;

-- =====================================
-- Insert Cleaned Data into Silver
-- =====================================
INSERT INTO SILVER_HOTEL_BOOKINGS
SELECT
    booking_id,
    hotel_id,
    INITCAP(TRIM(hotel_city)) AS hotel_city,
    customer_id,
    INITCAP(TRIM(customer_name)) AS customer_name,
    CASE
        WHEN customer_email LIKE '%@%.%' THEN LOWER(TRIM(customer_email))
        ELSE NULL
    END AS customer_email,
    TRY_TO_DATE(NULLIF(check_in_date, '')) AS check_in_date,
    TRY_TO_DATE(NULLIF(check_out_date, '')) AS check_out_date,
    room_type,
    TRY_TO_NUMBER(num_guests) AS num_guests,
    ABS(TRY_TO_NUMBER(total_amount)) AS total_amount,
    currency,
    CASE
        WHEN LOWER(booking_status) IN ('confirmeeed', 'confirmd')
            THEN 'Confirmed'
        ELSE INITCAP(TRIM(booking_status))
    END AS booking_status
FROM BRONZE_HOTEL_BOOKING
WHERE
    TRY_TO_DATE(check_in_date) IS NOT NULL
    AND TRY_TO_DATE(check_out_date) IS NOT NULL
    AND TRY_TO_DATE(check_out_date) >= TRY_TO_DATE(check_in_date);

-- =====================================
-- Preview Silver Data
-- =====================================
SELECT * 
FROM SILVER_HOTEL_BOOKINGS 
LIMIT 30;

-- =====================================
-- Create Gold Tables
-- =====================================

-- Daily Booking & Revenue Aggregation
CREATE OR REPLACE TABLE GOLD_AGG_DAILY_BOOKING AS
SELECT
    check_in_date AS booking_date,
    COUNT(*) AS total_booking,
    SUM(total_amount) AS total_revenue
FROM SILVER_HOTEL_BOOKINGS
GROUP BY check_in_date
ORDER BY booking_date;

-- Revenue by Hotel City
CREATE OR REPLACE TABLE GOLD_AGG_HOTEL_CITY_SALES AS
SELECT
    hotel_city,
    SUM(total_amount) AS total_revenue
FROM SILVER_HOTEL_BOOKINGS
GROUP BY hotel_city
ORDER BY total_revenue DESC;

-- Fully Cleaned Booking Table
CREATE OR REPLACE TABLE GOLD_BOOKING_CLEAN AS
SELECT
    booking_id,
    hotel_id,
    hotel_city,
    customer_id,
    customer_name,
    customer_email,
    check_in_date,
    check_out_date,
    room_type,
    num_guests,
    total_amount,
    currency,
    booking_status
FROM SILVER_HOTEL_BOOKINGS;

-- =====================================
-- Preview Gold Outputs
-- =====================================
SELECT * 
FROM GOLD_AGG_DAILY_BOOKING 
LIMIT 30;

SELECT * 
FROM GOLD_AGG_HOTEL_CITY_SALES 
LIMIT 30;

SELECT * 
FROM GOLD_BOOKING_CLEAN 
LIMIT 30;
