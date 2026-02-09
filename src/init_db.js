require('dotenv').config();
const { Pool } = require('pg');
const bcrypt = require('bcrypt');

const pool = new Pool({
    user: process.env.DB_USER || 'portal_admin',
    host: process.env.DB_HOST || '127.0.0.1',
    database: process.env.DB_NAME || 'smart_portal',
    password: process.env.DB_PASS || 'dbpassword',
    port: process.env.DB_PORT || 5432,
});

async function init() {
    try {
        console.log("Initializing Database...");
        await pool.query(`CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, username VARCHAR(50) UNIQUE, password_hash TEXT, is_admin BOOLEAN DEFAULT FALSE, status VARCHAR(20), bandwidth_mbps INTEGER, start_time TIME, end_time TIME, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)`);
        await pool.query("CREATE TABLE IF NOT EXISTS devices (id SERIAL PRIMARY KEY, user_id INTEGER REFERENCES users(id), mac VARCHAR(20) UNIQUE, name VARCHAR(50), status VARCHAR(20) DEFAULT 'PENDING', added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
        await pool.query("CREATE TABLE IF NOT EXISTS logs (id SERIAL PRIMARY KEY, username VARCHAR(50), action VARCHAR(50), details TEXT, timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
        await pool.query("CREATE TABLE IF NOT EXISTS vouchers (id SERIAL PRIMARY KEY, code VARCHAR(20) UNIQUE, is_used BOOLEAN DEFAULT FALSE, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, expires_at TIMESTAMP)");
        
        // Default Admin (Will trigger constraint if exists, which is fine)
        const hash = await bcrypt.hash("Jeffery#3218", 10);
        await pool.query("INSERT INTO users (username, password_hash, is_admin, status, bandwidth_mbps) VALUES ($1, $2, $3, 'APPROVED', NULL) ON CONFLICT (username) DO NOTHING", ["jeffery-uhrick", hash, true]);
        
        console.log("DB_SUCCESS");
        process.exit(0);
    } catch (e) {
        console.error("DB Init Failed:", e);
        process.exit(1);
    }
}
init();