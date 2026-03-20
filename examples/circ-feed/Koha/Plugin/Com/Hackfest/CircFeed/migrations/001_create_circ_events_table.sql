-- Migration 1: create_circ_events_table
-- Created: 2026-03-20

CREATE TABLE IF NOT EXISTS plugin_circ_feed_events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,
    borrowernumber INT DEFAULT NULL,
    itemnumber INT DEFAULT NULL,
    barcode VARCHAR(255) DEFAULT NULL,
    title VARCHAR(500) DEFAULT NULL,
    patron_name VARCHAR(255) DEFAULT NULL,
    library VARCHAR(255) DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_created (created_at),
    INDEX idx_type (event_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
