use rusqlite::Connection;
fn main() {
    let db_path = format!("{}\\Latera Team\\Latera\\Latera\\index\\latera_index.db", std::env::var("APPDATA").unwrap());
    println!("Opening: {}", db_path);
    let conn = Connection::open_with_flags(&db_path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
    let files: i64 = conn.query_row("SELECT COUNT(*) FROM files", [], |r| r.get(0)).unwrap();
    let chunks: i64 = conn.query_row("SELECT COUNT(*) FROM chunks", [], |r| r.get(0)).unwrap();
    let embs: i64 = conn.query_row("SELECT COUNT(*) FROM embeddings", [], |r| r.get(0)).unwrap();
    println!("files={}, chunks={}, embeddings={}", files, chunks, embs);
    if embs > 0 {
        let blob_len: i64 = conn.query_row("SELECT length(embedding) FROM embeddings LIMIT 1", [], |r| r.get(0)).unwrap();
        println!("embedding blob size: {} bytes = {} floats (f32)", blob_len, blob_len / 4);
    }
}
