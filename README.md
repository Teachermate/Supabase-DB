# TeacherMate Database

This repository contains the database schema, migrations, and configuration for the TeacherMate application.

## Directory Structure

- `migrations/`: SQL migration files for the database
- `config.toml`: Supabase configuration file
- `scripts/`: Utility scripts for database management
- `docker-compose.yml`: Docker Compose configuration for local development

## Getting Started

1. Clone this repository
2. Set up the environment variables (see `.env.example` in the main application repository)
3. Run `docker-compose up -d` to start the local Supabase instance
4. Run the migrations using the scripts in the `scripts/` directory

## Migration Files

The `migrations/` directory contains SQL files that define the database schema and any changes to it. These files are applied in order based on their filenames.

## Scripts

The `scripts/` directory contains utility scripts for database management, such as:

- `backup-database.ts`: Backs up the database
- `restore-latest-backup.ts`: Restores the latest database backup
- `run-migration.ts`: Runs database migrations
- `check-database.ts`: Checks the database status
- `monitor-database.ts`: Monitors the database for changes
- `reset-db.ts`: Resets the database to a clean state

## Docker Compose

The `docker-compose.yml` file defines the local development environment for Supabase, including the PostgreSQL database, storage, and authentication services.
