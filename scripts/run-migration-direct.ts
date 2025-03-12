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
    
    // Since we can't execute arbitrary SQL directly through the Supabase API,
    // we'll need to implement the migration using the available API methods.
    // This is a simplified example for creating the user_subscriptions table.
    
    console.log('Creating user_subscriptions table...');
    
    // Check if the table already exists
    const { data: tableExists, error: tableCheckError } = await supabase
      .from('user_subscriptions')
      .select('id')
      .limit(1);
    
    if (tableCheckError && tableCheckError.code !== 'PGRST204') {
      console.error('Error checking if table exists:', tableCheckError);
      console.log('Continuing with migration...');
    } else if (tableExists) {
      console.log('Table user_subscriptions already exists.');
      console.log('Migration completed.');
      return;
    }
    
    console.log('Table does not exist, proceeding with creation...');
    console.log('NOTE: For full SQL execution, please run this migration directly in the Supabase dashboard SQL editor.');
    console.log('The migration file is located at:', fullPath);
    
    // Print instructions for manual execution
    console.log('\n=== MANUAL MIGRATION INSTRUCTIONS ===');
    console.log('1. Go to the Supabase dashboard');
    console.log('2. Navigate to the SQL Editor');
    console.log('3. Create a new query');
    console.log('4. Paste the following SQL:');
    console.log(sql);
    console.log('5. Run the query');
    console.log('=== END OF INSTRUCTIONS ===\n');
    
    console.log('Migration script completed. Please follow the manual instructions above to complete the migration.');
  } catch (error) {
    console.error('Error running migration:', error);
    process.exit(1);
  }
}

// Get the migration file path from command line arguments
const migrationFilePath = process.argv[2];

if (!migrationFilePath) {
  console.error('Error: No migration file specified.');
  console.error('Usage: npx tsx scripts/run-migration-direct.ts <migration-file-path>');
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