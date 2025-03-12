import { createClient } from '@supabase/supabase-js';
import fs from 'fs';
import path from 'path';
import 'dotenv/config';

// Check for required environment variables
const supabaseUrl = process.env.VITE_SUPABASE_URL;
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseServiceRoleKey) {
  console.error('Error: Required environment variables are missing.');
  console.error('Make sure VITE_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are set.');
  process.exit(1);
}

// Initialize Supabase client with service role key
const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

async function runMigration(migrationFilePath: string) {
  console.log(`Running migration: ${migrationFilePath}`);

  try {
    // Read the migration file
    const fullPath = path.resolve(process.cwd(), migrationFilePath);
    const sql = fs.readFileSync(fullPath, 'utf8');
    
    console.log('Migration SQL:');
    console.log(sql);
    
    // Split the SQL into individual statements
    const statements = sql
      .split(';')
      .map(statement => statement.trim())
      .filter(statement => statement.length > 0);
    
    console.log(`Found ${statements.length} SQL statements to execute`);
    
    // Execute each statement
    for (let i = 0; i < statements.length; i++) {
      const statement = statements[i];
      console.log(`Executing statement ${i + 1}/${statements.length}:`);
      console.log(statement);
      
      const { data, error } = await supabase.rpc('execute_sql', {
        sql: statement
      });
      
      if (error) {
        console.error(`Error executing statement ${i + 1}:`, error);
        
        // Try to continue with the next statement
        console.log('Attempting to continue with the next statement...');
      } else {
        console.log(`Statement ${i + 1} executed successfully`);
      }
    }
    
    console.log('Migration completed');
  } catch (error) {
    console.error('Error running migration:', error);
    process.exit(1);
  }
}

// Get the migration file path from command line arguments
const migrationFilePath = process.argv[2];

if (!migrationFilePath) {
  console.error('Error: No migration file specified.');
  console.error('Usage: npx tsx scripts/run-migration.ts <migration-file-path>');
  process.exit(1);
}

// Run the migration
runMigration(migrationFilePath)
  .then(() => {
    console.log('Migration script completed successfully');
    process.exit(0);
  })
  .catch((error) => {
    console.error('Migration script failed:', error);
    process.exit(1);
  }); 