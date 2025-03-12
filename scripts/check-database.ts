import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import { backupDatabase } from './backup-database.js';

dotenv.config();

const supabaseUrl = process.env.SUPABASE_URL || 'http://127.0.0.1:54321';
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

const supabase = createClient(supabaseUrl, supabaseServiceKey);

async function checkDatabase() {
  try {
    console.log('Checking database state...');

    // Check if we can connect to the database
    const { data: healthCheck, error: healthError } = await supabase
      .from('system_status')
      .select('last_known_state')
      .limit(1);

    if (healthError) {
      console.error('Database health check failed:', healthError);
      process.exit(1);
    }

    // Check if we have any data in critical tables
    const tables = ['auth.users', 'user_profiles', 'schools', 'school_users'];
    const tableChecks = await Promise.all(
      tables.map(async (table) => {
        const { count, error } = await supabase
          .from(table)
          .select('*', { count: 'exact', head: true });

        return {
          table,
          count,
          error
        };
      })
    );

    const emptyTables = tableChecks.filter(check => check.count === 0);
    
    if (emptyTables.length > 0) {
      console.warn('Warning: The following tables are empty:', 
        emptyTables.map(t => t.table).join(', ')
      );
      
      // Create backup before potential data restoration
      await backupDatabase();
      
      // Here you could add logic to restore from a backup if needed
      console.log('Consider restoring data if this is unexpected');
    }

    // Check for recent resets
    const { data: resetCheck } = await supabase
      .from('system_status')
      .select('last_reset_time, last_known_state')
      .order('last_reset_time', { ascending: false })
      .limit(1)
      .single();

    if (resetCheck?.last_reset_time) {
      const resetTime = new Date(resetCheck.last_reset_time);
      const now = new Date();
      const hoursSinceReset = (now.getTime() - resetTime.getTime()) / (1000 * 60 * 60);

      if (hoursSinceReset < 1) {
        console.warn('Warning: Database was reset in the last hour!', {
          resetTime: resetCheck.last_reset_time,
          details: resetCheck.last_known_state
        });
      }
    }

    console.log('Database check completed successfully');
    return true;
  } catch (error) {
    console.error('Error checking database:', error);
    return false;
  }
}

// Execute if run directly
if (import.meta.url === `file://${process.argv[1]}`) {
  checkDatabase()
    .then(success => {
      if (!success) {
        process.exit(1);
      }
      process.exit(0);
    })
    .catch(error => {
      console.error('Check failed:', error);
      process.exit(1);
    });
}

export { checkDatabase }; 