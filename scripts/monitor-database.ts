import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import { backupDatabase } from './backup-database.js';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);
dotenv.config();

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseServiceKey) {
  console.error('Missing required environment variables');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseServiceKey);

interface SystemState {
  status: 'healthy' | 'warning' | 'error';
  lastCheck: Date;
  tables: Record<string, number>;
  lastBackup?: Date;
  warnings: string[];
  errors: string[];
}

class DatabaseMonitor {
  private checkInterval: NodeJS.Timeout | null = null;
  private readonly CHECK_INTERVAL_MS = 5 * 60 * 1000; // 5 minutes
  private readonly CRITICAL_TABLES = ['user_profiles', 'schools', 'school_users', 'content'];
  private lastKnownState: SystemState | null = null;

  async start() {
    try {
      // Initial check
      await this.checkSystem();
      
      // Start periodic checks
      this.checkInterval = setInterval(() => {
        this.checkSystem().catch(error => {
          console.error('Error during periodic check:', error);
        });
      }, this.CHECK_INTERVAL_MS);

      console.log('Database monitoring started');
    } catch (error) {
      console.error('Failed to start monitoring:', error);
      throw error;
    }
  }

  stop() {
    if (this.checkInterval) {
      clearInterval(this.checkInterval);
      this.checkInterval = null;
    }
    console.log('Database monitoring stopped');
  }

  private async checkSystem() {
    const state: SystemState = {
      status: 'healthy',
      lastCheck: new Date(),
      tables: {},
      warnings: [],
      errors: []
    };

    try {
      // Check database connectivity
      const { data: healthCheck, error: healthError } = await supabase.rpc('version');
      if (healthError) throw healthError;

      // Check critical tables
      for (const table of this.CRITICAL_TABLES) {
        const { count, error } = await supabase
          .from(table)
          .select('*', { count: 'exact', head: true });

        if (error) {
          state.errors.push(`Error checking table ${table}: ${error.message}`);
          continue;
        }

        state.tables[table] = count || 0;

        // Check for unexpected data loss
        if (this.lastKnownState?.tables[table] && count !== null) {
          const previousCount = this.lastKnownState.tables[table];
          const threshold = previousCount * 0.1; // 10% change threshold

          if (count < previousCount - threshold) {
            state.warnings.push(
              `Significant data loss detected in ${table}: Previous=${previousCount}, Current=${count}`
            );
            state.status = 'warning';
            
            // Trigger backup if significant data loss detected
            await this.handleDataLoss(state);
          }
        }
      }

      // Check last backup
      const { data: lastBackup } = await supabase
        .from('system_status')
        .select('last_backup_time')
        .order('last_backup_time', { ascending: false })
        .limit(1)
        .single();

      if (lastBackup?.last_backup_time) {
        state.lastBackup = new Date(lastBackup.last_backup_time);
        
        // Check if backup is too old (> 24 hours)
        const backupAge = Date.now() - state.lastBackup.getTime();
        if (backupAge > 24 * 60 * 60 * 1000) {
          state.warnings.push('No recent backup found (>24 hours)');
          await this.createBackup();
        }
      } else {
        state.warnings.push('No backup history found');
        await this.createBackup();
      }

      // Update status based on warnings and errors
      if (state.errors.length > 0) {
        state.status = 'error';
      } else if (state.warnings.length > 0) {
        state.status = 'warning';
      }

      // Save state
      await this.updateSystemStatus(state);
      this.lastKnownState = state;

      console.log('System check completed:', {
        status: state.status,
        warnings: state.warnings,
        errors: state.errors
      });

    } catch (error) {
      console.error('Error during system check:', error);
      state.status = 'error';
      state.errors.push(error instanceof Error ? error.message : 'Unknown error');
      await this.updateSystemStatus(state);
    }
  }

  private async handleDataLoss(state: SystemState) {
    try {
      // Create immediate backup
      await this.createBackup();

      // Log the incident
      await supabase.from('system_status').insert({
        status: 'error',
        last_known_state: {
          message: 'Unexpected data loss detected',
          state: state,
          timestamp: new Date().toISOString()
        }
      });

      // Notify (implement your notification system here)
      console.error('ALERT: Unexpected data loss detected', state);
    } catch (error) {
      console.error('Error handling data loss:', error);
    }
  }

  private async createBackup() {
    try {
      const result = await backupDatabase();
      if (!result.success) {
        throw new Error(result.error || 'Backup failed');
      }
      console.log('Backup created successfully');
    } catch (error) {
      console.error('Error creating backup:', error);
      throw error;
    }
  }

  private async updateSystemStatus(state: SystemState) {
    try {
      await supabase.from('system_status').insert({
        status: state.status === 'healthy' ? 'initialized' : 'error',
        last_known_state: state,
        error_count: state.errors.length,
        last_error: state.errors[0]
      });
    } catch (error) {
      console.error('Error updating system status:', error);
    }
  }
}

// Start monitoring if run directly
if (import.meta.url === `file://${process.argv[1]}`) {
  const monitor = new DatabaseMonitor();
  
  // Handle graceful shutdown
  process.on('SIGINT', () => {
    console.log('Shutting down monitor...');
    monitor.stop();
    process.exit(0);
  });

  monitor.start()
    .then(() => console.log('Monitoring started'))
    .catch(error => {
      console.error('Failed to start monitoring:', error);
      process.exit(1);
    });
}

export { DatabaseMonitor }; 