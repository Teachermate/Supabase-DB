import { exec } from 'child_process';
import { promisify } from 'util';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import dotenv from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const execAsync = promisify(exec);
dotenv.config();

const BACKUP_DIR = process.env.BACKUP_DIR || './backups';
const MAX_BACKUPS = parseInt(process.env.MAX_BACKUPS || '5', 10);
const RETENTION_DAYS = parseInt(process.env.BACKUP_RETENTION_DAYS || '7', 10);

interface BackupResult {
  success: boolean;
  path?: string;
  timestamp?: string;
  error?: string;
}

async function createBackupDirectory() {
  if (!fs.existsSync(BACKUP_DIR)) {
    fs.mkdirSync(BACKUP_DIR, { recursive: true });
  }
}

async function cleanOldBackups() {
  const files = fs.readdirSync(BACKUP_DIR)
    .filter(file => file.endsWith('.sql.gz'))
    .map(file => ({
      name: file,
      path: path.join(BACKUP_DIR, file),
      time: fs.statSync(path.join(BACKUP_DIR, file)).mtime.getTime()
    }))
    .sort((a, b) => b.time - a.time);

  // Remove old backups based on MAX_BACKUPS
  if (files.length > MAX_BACKUPS) {
    files.slice(MAX_BACKUPS).forEach(file => {
      fs.unlinkSync(file.path);
      console.log(`Removed old backup: ${file.name}`);
    });
  }

  // Remove backups older than RETENTION_DAYS
  const now = Date.now();
  const retentionMs = RETENTION_DAYS * 24 * 60 * 60 * 1000;
  files.forEach(file => {
    if (now - file.time > retentionMs) {
      fs.unlinkSync(file.path);
      console.log(`Removed expired backup: ${file.name}`);
    }
  });
}

async function backupDatabase(): Promise<BackupResult> {
  try {
    await createBackupDirectory();
    
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const backupPath = path.join(BACKUP_DIR, `db_backup_${timestamp}.sql`);
    const compressedPath = `${backupPath}.gz`;
    
    const pgPassword = process.env.POSTGRES_PASSWORD || 'postgres';
    const pgHost = process.env.POSTGRES_HOST || 'localhost';
    const pgPort = process.env.POSTGRES_PORT || '54322';
    const pgUser = process.env.POSTGRES_USER || 'postgres';
    const pgDatabase = process.env.POSTGRES_DB || 'postgres';

    // Set PGPASSWORD environment variable for pg_dump
    process.env.PGPASSWORD = pgPassword;

    // Create backup and pipe directly to gzip
    const command = `pg_dump -h ${pgHost} -p ${pgPort} -U ${pgUser} -d ${pgDatabase} -F p | gzip > ${compressedPath}`;
    
    console.log('Creating compressed database backup...');
    const { stdout, stderr } = await execAsync(command);
    
    if (stderr) {
      console.warn('Warnings during backup:', stderr);
    }

    // Verify the backup file exists and has content
    if (!fs.existsSync(compressedPath) || fs.statSync(compressedPath).size === 0) {
      throw new Error('Backup file is empty or was not created');
    }

    console.log(`Backup created successfully at: ${compressedPath}`);
    
    // Clean up old backups
    await cleanOldBackups();
    
    // Update system status in database
    const updateCommand = `psql -h ${pgHost} -p ${pgPort} -U ${pgUser} -d ${pgDatabase} -c "
      INSERT INTO system_status (status, last_known_state, last_backup_time)
      VALUES ('backup', jsonb_build_object('backup_file', '${path.basename(compressedPath)}'), CURRENT_TIMESTAMP)
    "`;
    
    await execAsync(updateCommand);
    
    return {
      success: true,
      path: compressedPath,
      timestamp: timestamp
    };
  } catch (error) {
    console.error('Error creating backup:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error during backup'
    };
  }
}

// Execute backup if run directly
if (import.meta.url === `file://${process.argv[1]}`) {
  backupDatabase()
    .then((result) => {
      if (result.success) {
        console.log('Backup completed successfully');
        process.exit(0);
      } else {
        console.error('Backup failed:', result.error);
        process.exit(1);
      }
    })
    .catch(error => {
      console.error('Backup failed:', error);
      process.exit(1);
    });
}

export { backupDatabase }; 