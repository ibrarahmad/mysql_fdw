\set MYSQL_HOST			'\'localhost\''
\set MYSQL_PORT			'\'3306\''
\set MYSQL_USER_NAME	'\'edb\''
\set MYSQL_PASS			'\'edb\''

-- Before running this file User must create database mysql_fdw_regress on
-- MySQL with all permission for 'edb' user with 'edb' password and ran
-- mysql_init.sh file to create tables.

\c contrib_regression
CREATE EXTENSION IF NOT EXISTS mysql_fdw;
CREATE SERVER mysql_svr FOREIGN DATA WRAPPER mysql_fdw
  OPTIONS (host :MYSQL_HOST, port :MYSQL_PORT);
CREATE USER MAPPING FOR public SERVER mysql_svr
  OPTIONS (username :MYSQL_USER_NAME, password :MYSQL_PASS);

-- Create foreign tables
CREATE FOREIGN TABLE f_mysql_test(a int, b int)
  SERVER mysql_svr OPTIONS (dbname 'mysql_fdw_regress', table_name 'mysql_test');
CREATE FOREIGN TABLE fdw126_ft1(stu_id int, stu_name varchar(255), stu_dept int)
  SERVER mysql_svr OPTIONS (dbname 'mysql_fdw_regress1', table_name 'student');
CREATE FOREIGN TABLE fdw126_ft2(stu_id int, stu_name varchar(255))
  SERVER mysql_svr OPTIONS (table_name 'student');
CREATE FOREIGN TABLE fdw126_ft3(a int, b varchar(255))
  SERVER mysql_svr OPTIONS (dbname 'mysql_fdw_regress1', table_name 'numbers');
CREATE FOREIGN TABLE fdw126_ft4(a int, b varchar(255))
  SERVER mysql_svr OPTIONS (dbname 'mysql_fdw_regress1', table_name 'nosuchtable');
CREATE FOREIGN TABLE fdw126_ft5(a int, b varchar(255))
  SERVER mysql_svr OPTIONS (dbname 'mysql_fdw_regress2', table_name 'numbers');
CREATE FOREIGN TABLE fdw126_ft6(stu_id int, stu_name varchar(255))
  SERVER mysql_svr OPTIONS (table_name 'mysql_fdw_regress1.student');
CREATE FOREIGN TABLE f_empdata(emp_id int, emp_dat bytea)
  SERVER mysql_svr OPTIONS (dbname 'mysql_fdw_regress', table_name 'empdata');
CREATE FOREIGN TABLE fdw193_ft1(stu_id varchar(10), stu_name varchar(255), stu_dept int)
  SERVER mysql_svr OPTIONS (dbname 'mysql_fdw_regress1', table_name 'student1');


-- Operation on blob data.
INSERT INTO f_empdata VALUES (1, decode ('01234567', 'hex'));
SELECT count(*) FROM f_empdata ORDER BY 1;
SELECT emp_id, emp_dat FROM f_empdata ORDER BY 1;
UPDATE f_empdata SET emp_dat = decode ('0123', 'hex');
SELECT emp_id, emp_dat FROM f_empdata ORDER BY 1;

-- FDW-126: Insert/update/delete statement failing in mysql_fdw by picking
-- wrong database name.

-- Verify the INSERT/UPDATE/DELETE operations on another foreign table which
-- resides in the another database in MySQL.  The previous commands performs
-- the operation on foreign table created for tables in mysql_fdw_regress
-- MySQL database.  Below operations will be performed for foreign table
-- created for table in mysql_fdw_regress1 MySQL database.
INSERT INTO fdw126_ft1 VALUES(1, 'One', 101);
UPDATE fdw126_ft1 SET stu_name = 'one' WHERE stu_id = 1;
DELETE FROM fdw126_ft1 WHERE stu_id = 1;

-- Select on f_mysql_test foreign table which is created for mysql_test table
-- from mysql_fdw_regress MySQL database.  This call is just to cross verify if
-- everything is working correctly.
SELECT a, b FROM f_mysql_test ORDER BY 1, 2;

-- Insert into fdw126_ft2 table which does not have dbname specified while
-- creating the foreign table, so it will consider the schema name of foreign
-- table as database name and try to connect/lookup into that database.  Will
-- throw an error.
INSERT INTO fdw126_ft2 VALUES(2, 'Two');

-- Check with the same table name from different database. fdw126_ft3 is
-- pointing to the mysql_fdw_regress1.numbers and not mysql_fdw_regress.numbers
-- table.  INSERT/UPDATE/DELETE should be failing.  SELECT will return no rows.
INSERT INTO fdw126_ft3 VALUES(1, 'One');
SELECT a, b FROM fdw126_ft3 ORDER BY 1, 2 LIMIT 1;
UPDATE fdw126_ft3 SET b = 'one' WHERE a = 1;
DELETE FROM fdw126_ft3 WHERE a = 1;

-- Check when table_name is given in database.table form in foreign table
-- should error out as syntax error
INSERT INTO fdw126_ft6 VALUES(1, 'One');

-- Perform the ANALYZE on the foreign table which is not present on the remote
-- side.  Should not crash.
-- The database is present but not the target table.
ANALYZE fdw126_ft4;
-- The database itself is not present.
ANALYZE fdw126_ft5;
-- Some other variant of analyze and vacuum.
-- when table exists, should give skip-warning
VACUUM f_empdata;
VACUUM FULL f_empdata;
VACUUM FREEZE f_empdata;
ANALYZE f_empdata;
ANALYZE f_empdata(emp_id);
VACUUM ANALYZE f_empdata;

-- Verify the before update trigger which modifies the column value which is not
-- part of update statement.
CREATE FUNCTION before_row_update_func() RETURNS TRIGGER AS $$
BEGIN
  NEW.stu_name := NEW.stu_name || ' trigger updated!';
	RETURN NEW;
  END
$$ language plpgsql;

CREATE TRIGGER before_row_update_trig
BEFORE UPDATE ON fdw126_ft1
FOR EACH ROW EXECUTE PROCEDURE before_row_update_func();

INSERT INTO fdw126_ft1 VALUES(1, 'One', 101);
EXPLAIN (verbose, costs off)
UPDATE fdw126_ft1 SET stu_dept = 201 WHERE stu_id = 1;
UPDATE fdw126_ft1 SET stu_dept = 201 WHERE stu_id = 1;
SELECT * FROM fdw126_ft1 ORDER BY stu_id;

-- Throw an error when target list has row identifier column.
UPDATE fdw126_ft1 SET stu_dept = 201, stu_id = 10  WHERE stu_id = 1;

-- Throw an error when before row update trigger modify the row identifier
-- column (int column) value.
CREATE OR REPLACE FUNCTION before_row_update_func() RETURNS TRIGGER AS $$
BEGIN
  NEW.stu_name := NEW.stu_name || ' trigger updated!';
  NEW.stu_id = 20;
  RETURN NEW;
  END
$$ language plpgsql;

UPDATE fdw126_ft1 SET stu_dept = 301 WHERE stu_id = 1;

-- Verify the before update trigger which modifies the column value which is
-- not part of update statement.
CREATE OR REPLACE FUNCTION before_row_update_func() RETURNS TRIGGER AS $$
BEGIN
  NEW.stu_name := NEW.stu_name || ' trigger updated!';
  RETURN NEW;
  END
$$ language plpgsql;

CREATE TRIGGER before_row_update_trig1
BEFORE UPDATE ON fdw193_ft1
FOR EACH ROW EXECUTE PROCEDURE before_row_update_func();

INSERT INTO fdw193_ft1 VALUES('aa', 'One', 101);
EXPLAIN (verbose, costs off)
UPDATE fdw193_ft1 SET stu_dept = 201 WHERE stu_id = 'aa';
UPDATE fdw193_ft1 SET stu_dept = 201 WHERE stu_id = 'aa';
SELECT * FROM fdw193_ft1 ORDER BY stu_id;

-- Throw an error when before row update trigger modify the row identifier
-- column (varchar column) value.
CREATE OR REPLACE FUNCTION before_row_update_func() RETURNS TRIGGER AS $$
BEGIN
  NEW.stu_name := NEW.stu_name || ' trigger updated!';
  NEW.stu_id = 'bb';
  RETURN NEW;
  END
$$ language plpgsql;

UPDATE fdw193_ft1 SET stu_dept = 301 WHERE stu_id = 'aa';

-- Verify the NULL assignment scenario.
CREATE OR REPLACE FUNCTION before_row_update_func() RETURNS TRIGGER AS $$
BEGIN
  NEW.stu_name := NEW.stu_name || ' trigger updated!';
  NEW.stu_id = NULL;
  RETURN NEW;
  END
$$ language plpgsql;

UPDATE fdw193_ft1 SET stu_dept = 401 WHERE stu_id = 'aa';

-- Cleanup
DELETE FROM fdw126_ft1;
DELETE FROM f_empdata;
DELETE FROM fdw193_ft1;
DROP FOREIGN TABLE f_mysql_test;
DROP FOREIGN TABLE fdw126_ft1;
DROP FOREIGN TABLE fdw126_ft2;
DROP FOREIGN TABLE fdw126_ft3;
DROP FOREIGN TABLE fdw126_ft4;
DROP FOREIGN TABLE fdw126_ft5;
DROP FOREIGN TABLE fdw126_ft6;
DROP FOREIGN TABLE f_empdata;
DROP FOREIGN TABLE fdw193_ft1;
DROP FUNCTION before_row_update_func();
DROP USER MAPPING FOR public SERVER mysql_svr;
DROP SERVER mysql_svr;
DROP EXTENSION mysql_fdw;
