import { createClient } from '@supabase/supabase-js'
import dotenv from 'dotenv'
import { Database } from '../src/lib/database.types'
import { execSync } from 'child_process'

dotenv.config()

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!supabaseUrl || !supabaseServiceKey) {
  console.error('Missing required environment variables')
  process.exit(1)
}

const supabase = createClient<Database>(supabaseUrl, supabaseServiceKey)

async function resetDatabase() {
  try {
    console.log('Starting database reset process...')

    // Log the reset event
    await supabase.rpc('log_system_event', {
      p_status: 'reset',
      p_state: {
        message: 'Starting database reset',
        timestamp: new Date().toISOString()
      }
    })

    // Stop Supabase services
    console.log('Stopping Supabase services...')
    execSync('supabase stop', { stdio: 'inherit' })

    // Remove Docker volumes
    console.log('Removing Docker volumes...')
    const volumes = execSync('docker volume ls --filter label=com.supabase.cli.project=Bolt-2-Cursor --format "{{.Name}}"')
      .toString()
      .trim()
      .split('\n')
      .filter(Boolean)

    if (volumes.length > 0) {
      execSync(`docker volume rm ${volumes.join(' ')}`, { stdio: 'inherit' })
    }

    // Start Supabase services
    console.log('Starting Supabase services...')
    execSync('supabase start', { stdio: 'inherit' })

    // Run migrations
    console.log('Running migrations...')
    execSync('supabase db reset', { stdio: 'inherit' })

    // Create test users
    console.log('Creating test users...')
    execSync('npx tsx scripts/create-test-users.ts', { stdio: 'inherit' })

    console.log('Database reset completed successfully')

    // Log successful completion
    await supabase.rpc('log_system_event', {
      p_status: 'initialized',
      p_state: {
        message: 'Database reset completed successfully',
        timestamp: new Date().toISOString()
      }
    })

  } catch (error) {
    console.error('Error during database reset:', error)

    // Log the error
    await supabase.rpc('log_system_event', {
      p_status: 'error',
      p_state: {
        message: 'Database reset failed',
        timestamp: new Date().toISOString()
      },
      p_error: {
        message: error instanceof Error ? error.message : String(error),
        stack: error instanceof Error ? error.stack : undefined
      }
    })

    process.exit(1)
  }
}

// Run the reset process
resetDatabase() 