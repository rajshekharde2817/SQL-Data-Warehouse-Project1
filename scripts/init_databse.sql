/*
=================================================
Creating a database 'DataWarehouse1' and Schemas
=================================================
Script Purpose:
  This script is to create a new database called 'DataWarehouse1' after checking if it already exists.
  If the database exists, the script drops it and recreates it. Additionally, the scripts sets up three schemas in 
  the database: 'bronze', 'silver' and 'gold'.

Warning:
  Running this script will drop the entire 'DataWarehouse1' database and recreates it. While droping all the existing data will be deleted.
  Please ensure you have proper backups of the data before running this script.
*/


USE master;
GO

-- Dropping and recreating the database 'DataWarehouse1'
IF EXISTS (Select 1 from sys.databases where name= 'DataWarehouse1')
  Begin
    ALTER Database DataWarehouse1 SET Single_User with Rollback Immediate;
    Drop database DataWarehouse1;
END;
Go

-- Creating the 'DataWarehouse1' database
Create Database DataWarehouse1
GO
USE DataWarehouse1
GO

-- Creating schemas
Create Schema bronze;
Go
  
Create Schema silver;
Go

Create Schema gold;
Go
