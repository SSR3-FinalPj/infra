-- PostgreSQL 초기화 스크립트
-- Airflow를 위한 데이터베이스 및 사용자 생성 (Idempotent)

-- Airflow 사용자가 존재하지 않을 경우에만 생성
DO
$do$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles
      WHERE  rolname = 'airflow') THEN

      CREATE ROLE airflow LOGIN PASSWORD 'airflow';
   END IF;
END
$do$;

-- Airflow 데이터베이스가 존재하지 않을 경우에만 생성  
SELECT 'CREATE DATABASE airflow OWNER airflow'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'airflow')\gexec

-- Airflow 사용자에게 권한 부여 (항상 실행 - 권한은 중복 부여해도 문제없음)
GRANT ALL PRIVILEGES ON DATABASE airflow TO airflow;

-- 연결 확인을 위한 출력
SELECT 'Airflow database and user setup completed' as status;