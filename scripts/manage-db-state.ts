import { createClient } from '@supabase/supabase-js'
import dotenv from 'dotenv'
import { Database } from '../src/lib/database.types'

dotenv.config()

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!supabaseUrl || !supabaseServiceKey) {
  console.error('Missing required environment variables')
  process.exit(1)
}

const supabase = createClient<Database>(supabaseUrl, supabaseServiceKey)

type SystemStatus = 'initialized' | 'reset' | 'backup' | 'restore' | 'error'

async function logSystemEvent(
  status: SystemStatus,
  state?: Record<string, any>,
  error?: Record<string, any>
) {
  try {
    const { data, error: dbError } = await supabase.rpc('log_system_event', {
      p_status: status,
      p_state: state || {},
      p_error: error
    })

    if (dbError) throw dbError
    console.log(`Successfully logged system event: ${status}`)
    return data
  } catch (err) {
    console.error('Failed to log system event:', err)
    throw err
  }
}

async function getSystemStatus() {
  try {
    const { data, error } = await supabase
      .from('system_status')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(1)
      .single()

    if (error) throw error
    return data
  } catch (err) {
    console.error('Failed to get system status:', err)
    throw err
  }
}

async function checkDatabaseHealth() {
  try {
    // Check if we can connect to the database
    const { data: healthCheck, error: healthError } = await supabase.rpc('version')
    if (healthError) throw healthError

    // Get table statistics
    const tables = ['user_profiles', 'schools', 'school_users', 'content']
    const tableStats: Record<string, number> = {}

    for (const table of tables) {
      const { count, error } = await supabase
        .from(table)
        .select('*', { count: 'exact', head: true })

      if (error) throw error
      tableStats[table] = count || 0
    }

    return {
      connected: true,
      version: healthCheck,
      tableStats
    }
  } catch (err) {
    console.error('Database health check failed:', err)
    throw err
  }
}

async function main() {
  const command = process.argv[2]
  
  try {
    switch (command) {
      case 'status':
        const status = await getSystemStatus()
        console.log('Current system status:', status)
        break
        
      case 'health':
        const health = await checkDatabaseHealth()
        console.log('Database health:', health)
        break
        
      case 'reset':
        await logSystemEvent('reset', {
          message: 'Manual database reset triggered',
          timestamp: new Date().toISOString()
        })
        console.log('Database reset logged')
        break
        
      case 'backup':
        await logSystemEvent('backup', {
          message: 'Manual backup triggered',
          timestamp: new Date().toISOString()
        })
        console.log('Backup event logged')
        break
        
      default:
        console.log(`
Available commands:
  status  - Get current system status
  health  - Check database health
  reset   - Log a database reset event
  backup  - Log a backup event
        `)
    }
  } catch (err) {
    console.error('Error:', err)
    await logSystemEvent('error', {
      command,
      timestamp: new Date().toISOString()
    }, {
      message: err instanceof Error ? err.message : String(err),
      stack: err instanceof Error ? err.stack : undefined
    })
    process.exit(1)
  }
}

main() 