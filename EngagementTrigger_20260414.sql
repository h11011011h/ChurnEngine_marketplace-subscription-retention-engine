-- 1. Create Users Table
CREATE TABLE Users (
    UserID INT PRIMARY KEY,
    SignupDate DATE,
    AcquisitionCost DECIMAL(10,2), -- Used for CAC [cite: 100]
    UserType VARCHAR(50) -- B2C or B2B [cite: 38]
);

-- 2. Create Subscriptions Table
CREATE TABLE Subscriptions (
    SubscriptionID INT PRIMARY KEY IDENTITY(1,1),
    UserID INT,
    PaymentDate DATE,
    PaymentAmount DECIMAL(10,2), -- Monthly subscription fee
    Status VARCHAR(20) -- Active or Cancelled
);

-- 3. Create ActivityLogs Table
CREATE TABLE ActivityLogs (
    ActivityID INT PRIMARY KEY IDENTITY(1,1),
    UserID INT,
    ActivityDate DATE,
    ActivityType VARCHAR(50) -- 'QuestionAsked', 'Login', 'ExpertInteraction' [cite: 86, 159]
);

-------------------------------
-------------------------------
-------------------------------
-------------------------------
-------------------------------

-- Populate Users
INSERT INTO Users (UserID, SignupDate, AcquisitionCost, UserType) VALUES 
(101, '2024-01-01', 50.00, 'B2C'), -- High LTV potential
(102, '2024-01-05', 150.00, 'B2B'), -- High CAC, requires retention focus [cite: 126]
(103, '2024-01-10', 45.00, 'B2C');

-- Populate Subscriptions (Simulating recurring revenue over 3 months)
INSERT INTO Subscriptions (UserID, PaymentDate, PaymentAmount, Status) VALUES 
(101, '2024-01-01', 30.00, 'Active'), (101, '2024-02-01', 30.00, 'Active'), (101, '2024-03-01', 30.00, 'Active'),
(102, '2024-01-05', 100.00, 'Active'), (102, '2024-02-05', 100.00, 'Active'), (102, '2024-03-05', 100.00, 'Active'),
(103, '2024-01-10', 25.00, 'Active'), (103, '2024-02-10', 25.00, 'Cancelled'); -- User 103 Churned [cite: 98]

-- Populate ActivityLogs (Creating the "Churn Signal")
-- User 101: Consistent activity (Healthy) 
INSERT INTO ActivityLogs (UserID, ActivityDate, ActivityType) VALUES 
(101, '2024-01-15', 'QuestionAsked'), (101, '2024-02-15', 'QuestionAsked'), (101, '2024-03-15', 'QuestionAsked');

-- User 102: Dropping activity in Month 3 (THE CHURN SIGNAL [cite: 104])
INSERT INTO ActivityLogs (UserID, ActivityDate, ActivityType) VALUES 
(102, '2024-01-10', 'QuestionAsked'), (102, '2024-01-20', 'QuestionAsked'), -- 2 questions in Jan
(102, '2024-02-05', 'QuestionAsked'), (102, '2024-02-25', 'QuestionAsked'), -- 2 questions in Feb
(102, '2024-03-10', 'Login'); -- 0 questions in March (Engagement dropped > 50%) [cite: 104]

-- User 103: Stopped logging in entirely after Feb
INSERT INTO ActivityLogs (UserID, ActivityDate, ActivityType) VALUES 
(103, '2024-01-15', 'QuestionAsked'), (103, '2024-02-01', 'Login');

-------------------------------
-------------------------------
-------------------------------
-------------------------------
------------------------------- 
------------------------------- select * from ActivityLogs

-- 1. Add the User
INSERT INTO Users (UserID, SignupDate, AcquisitionCost, UserType) 
VALUES (104, '2024-02-01', 40.00, 'B2C');

-- 2. Add their Subscription (Still Active, which is why it's a 'signal' not a 'loss' yet)
INSERT INTO Subscriptions (UserID, PaymentDate, PaymentAmount, Status) 
VALUES (104, '2024-02-01', 25.00, 'Active'), 
       (104, '2024-03-01', 25.00, 'Active');

-- 3. Add High Activity in Month 1 (Baseline)
INSERT INTO ActivityLogs (UserID, ActivityDate, ActivityType) VALUES 
(104, '2024-02-05', 'QuestionAsked'),
(104, '2024-02-10', 'QuestionAsked'),
(104, '2024-02-15', 'ExpertInteraction'),
(104, '2024-02-20', 'QuestionAsked'); -- 4 Actions in Feb

-- 4. Add Minimal Activity in Month 2 (The Signal)
INSERT INTO ActivityLogs (UserID, ActivityDate, ActivityType) VALUES 
(104, '2024-03-05', 'Login'); -- Only 1 Login, 0 Questions/Interactions in March

-------------------------------
-------------------------------
-------------------------------
-------------------------------
------------------------------- 
-------------------------------


WITH MonthSeries AS (
    -- Creates a list of all months present in your logs
    SELECT DISTINCT EOMONTH(ActivityDate) AS ActivityMonth FROM ActivityLogs
),
UserSeries AS (
    -- Creates a list of all users
    SELECT DISTINCT UserID FROM Users
),
UserMonthGrid AS (
    -- Ensures every user has a row for every month
    SELECT u.UserID, m.ActivityMonth
    FROM UserSeries u
    CROSS JOIN MonthSeries m
),
MonthlyActivity AS (
    SELECT 
        grid.UserID,
        grid.ActivityMonth,
        COUNT(logs.ActivityID) AS ActionCount
    FROM UserMonthGrid grid
    LEFT JOIN ActivityLogs logs 
        ON grid.UserID = logs.UserID 
        AND grid.ActivityMonth = EOMONTH(logs.ActivityDate)
        AND logs.ActivityType IN ('QuestionAsked', 'ExpertInteraction')
    GROUP BY grid.UserID, grid.ActivityMonth
),
ActivityTrends AS (
    SELECT 
        UserID,
        ActivityMonth,
        ActionCount,
        LAG(ActionCount) OVER (PARTITION BY UserID ORDER BY ActivityMonth) AS PreviousMonthActionCount
    FROM MonthlyActivity
)
SELECT 
    UserID,
    ActivityMonth,
    ActionCount AS CurrentMonthActions,
    PreviousMonthActionCount,
    CASE 
        WHEN PreviousMonthActionCount = 0 THEN NULL 
        ELSE (CAST(ActionCount AS FLOAT) - PreviousMonthActionCount) / PreviousMonthActionCount 
    END AS EngagementDropScore
FROM ActivityTrends
WHERE 
    -- Now catches drops to ZERO (like User 102 and 104)
    (CAST(ActionCount AS FLOAT) / NULLIF(PreviousMonthActionCount, 0)) <= 0.5
    AND PreviousMonthActionCount >= 2;