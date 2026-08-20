use std::collections::HashMap;
use std::fs;
use std::path::Path;

use crate::json::Json;
use crate::util::{decode_multiline, parse_kv_lines, read_text_if_exists, AppResult};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WorkItem {
    pub id: String,
    pub source: String,
    pub status: String,
    pub kind: String,
    pub reason: String,
    pub repo: String,
    pub title: String,
    pub url: String,
    pub summary: String,
    pub updated_at: String,
    pub thread_key: String,
    pub sort_epoch: u64,
}

pub fn recent_work(tasks_dir: &Path) -> AppResult<Vec<WorkItem>> {
    if !tasks_dir.exists() {
        return Ok(Vec::new());
    }
    let mut items: Vec<WorkItem> = Vec::new();
    for entry in fs::read_dir(tasks_dir)? {
        let entry = entry?;
        if !entry.file_type()?.is_dir() {
            continue;
        }
        let task_id = entry.file_name().to_string_lossy().into_owned();
        let meta = read_task_metadata(&entry.path());
        if let Some(item) = work_item_from_metadata(task_id, meta) {
            items.push(item);
        }
    }
    items.sort_by(|left, right| {
        right
            .sort_epoch
            .cmp(&left.sort_epoch)
            .then_with(|| right.id.cmp(&left.id))
    });
    Ok(items)
}

fn read_task_metadata(task_dir: &Path) -> HashMap<String, String> {
    let mut meta: HashMap<String, String> = HashMap::new();
    if let Ok(Some(contents)) = read_text_if_exists(&task_dir.join("snapshot/task-summary.env")) {
        for (key, value) in parse_kv_lines(&contents) {
            meta.insert(key, value);
        }
    }
    if let Ok(Some(contents)) = read_text_if_exists(&task_dir.join("task.env")) {
        for (key, value) in parse_kv_lines(&contents) {
            meta.insert(key, value);
        }
    } else if !meta.is_empty() && !meta.contains_key("status") {
        meta.insert("status".to_string(), "running".to_string());
    }
    meta
}

pub fn work_payload(tasks_dir: &Path) -> AppResult<String> {
    let items = recent_work(tasks_dir)?;
    Ok(work_items_to_json(&items))
}

pub fn work_items_to_json(items: &[WorkItem]) -> String {
    Json::Object(vec![
        ("total".to_string(), Json::Number(items.len() as i64)),
        (
            "items".to_string(),
            Json::Array(items.iter().map(work_item_to_json).collect()),
        ),
    ])
    .encode()
}

fn work_item_to_json(item: &WorkItem) -> Json {
    Json::Object(vec![
        ("id".to_string(), Json::str(item.id.clone())),
        ("source".to_string(), Json::str(item.source.clone())),
        ("status".to_string(), Json::str(item.status.clone())),
        ("kind".to_string(), Json::str(item.kind.clone())),
        ("reason".to_string(), Json::str(item.reason.clone())),
        ("repo".to_string(), Json::str(item.repo.clone())),
        ("title".to_string(), Json::str(item.title.clone())),
        ("url".to_string(), Json::str(item.url.clone())),
        ("summary".to_string(), Json::str(item.summary.clone())),
        ("updated_at".to_string(), Json::str(item.updated_at.clone())),
    ])
}

fn work_item_from_metadata(
    task_id: String,
    meta: HashMap<String, String>,
) -> Option<WorkItem> {
    if meta.is_empty() {
        return None;
    }
    let repo = meta.get("repo").cloned().unwrap_or_default();
    let summary = decode_multiline(meta.get("summary").map(String::as_str).unwrap_or(""));
    let mut title = decode_multiline(meta.get("title").map(String::as_str).unwrap_or(""));
    if title.is_empty() {
        title = summary
            .lines()
            .next()
            .unwrap_or("")
            .trim()
            .to_string();
    }
    if title.is_empty() {
        title = task_id.clone();
    }
    let thread_key = meta.get("thread_key").cloned().unwrap_or_default();
    let url = meta
        .get("url")
        .cloned()
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| html_url_from_thread_key(&thread_key));
    let sort_epoch = sort_epoch(&task_id, &meta);
    Some(WorkItem {
        id: task_id,
        source: meta
            .get("source")
            .cloned()
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "task".to_string()),
        status: meta
            .get("status")
            .cloned()
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "unknown".to_string()),
        kind: meta.get("kind").cloned().unwrap_or_default(),
        reason: meta.get("reason").cloned().unwrap_or_default(),
        repo,
        title,
        url,
        summary,
        updated_at: display_timestamp(sort_epoch, meta.get("updated_at").map(String::as_str)),
        thread_key,
        sort_epoch,
    })
}

fn sort_epoch(task_id: &str, meta: &HashMap<String, String>) -> u64 {
    for key in ["finished_at", "started_at"] {
        if let Some(value) = meta.get(key).and_then(|raw| raw.parse::<u64>().ok()) {
            if value > 0 {
                return value;
            }
        }
    }
    task_id
        .split('-')
        .nth(1)
        .and_then(|raw| raw.parse::<u64>().ok())
        .unwrap_or(0)
}

fn display_timestamp(epoch: u64, fallback: Option<&str>) -> String {
    if epoch > 0 {
        return format_utc_iso(epoch);
    }
    fallback.unwrap_or("").to_string()
}

fn html_url_from_thread_key(thread_key: &str) -> String {
    let path = thread_key.trim_start_matches("/repos/");
    if let Some((repo, rest)) = path.split_once("/pulls/") {
        return format!("https://github.com/{repo}/pull/{rest}");
    }
    if let Some((repo, rest)) = path.split_once("/issues/") {
        return format!("https://github.com/{repo}/issues/{rest}");
    }
    String::new()
}

fn format_utc_iso(epoch_seconds: u64) -> String {
    let days = (epoch_seconds / 86_400) as i64;
    let seconds_in_day = (epoch_seconds % 86_400) as u32;
    let hour = seconds_in_day / 3_600;
    let minute = (seconds_in_day % 3_600) / 60;
    let second = seconds_in_day % 60;
    let (year, month, day) = civil_from_days(days);
    format!("{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}Z")
}

fn civil_from_days(mut days: i64) -> (i32, u32, u32) {
    days += 719_468;
    let era = if days >= 0 { days } else { days - 146_096 } / 146_097;
    let day_of_era = (days - era * 146_097) as u64;
    let year_of_era = (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096)
        / 365;
    let year = (year_of_era as i64 + era * 400) as i32;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let mp = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if month <= 2 { year + 1 } else { year };
    (year, month as u32, day as u32)
}

#[cfg(test)]
mod tests {
    use super::{html_url_from_thread_key, recent_work, work_item_from_metadata};
    use crate::util::write_text;
    use std::collections::HashMap;

    #[test]
    fn derives_github_url_from_thread_key() {
        assert_eq!(
            html_url_from_thread_key("/repos/serenakeyitan/tokentorrent/pulls/77"),
            "https://github.com/serenakeyitan/tokentorrent/pull/77"
        );
    }

    #[test]
    fn author_follow_task_becomes_a_work_item() {
        let mut meta = HashMap::new();
        meta.insert("repo".to_string(), "serenakeyitan/tokentorrent".to_string());
        meta.insert(
            "title".to_string(),
            "feat: credential-only".to_string(),
        );
        meta.insert("status".to_string(), "handled".to_string());
        meta.insert("source".to_string(), "author-follow".to_string());
        meta.insert(
            "thread_key".to_string(),
            "/repos/serenakeyitan/tokentorrent/pulls/77".to_string(),
        );
        meta.insert("started_at".to_string(), "1787190109".to_string());
        meta.insert("finished_at".to_string(), "1787191000".to_string());
        let item = work_item_from_metadata("task-1787190109-abc".to_string(), meta).unwrap();
        assert_eq!(item.source, "author-follow");
        assert_eq!(item.status, "handled");
        assert_eq!(
            item.url,
            "https://github.com/serenakeyitan/tokentorrent/pull/77"
        );
        assert_eq!(
            item.thread_key,
            "/repos/serenakeyitan/tokentorrent/pulls/77"
        );
        assert_eq!(item.sort_epoch, 1_787_191_000);
        assert!(item.updated_at.starts_with("2026-"));
    }

    #[test]
    fn lists_newest_tasks_first() {
        let dir = std::env::temp_dir().join(format!(
            "breeze-work-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(dir.join("task-1")).unwrap();
        std::fs::create_dir_all(dir.join("task-2")).unwrap();
        write_text(
            &dir.join("task-1/task.env"),
            "repo=acme/one\ntitle=old\nstatus=handled\nsource=author-follow\nfinished_at=100\n",
        )
        .unwrap();
        write_text(
            &dir.join("task-2/task.env"),
            "repo=acme/two\ntitle=new\nstatus=running\nsource=author-follow\nstarted_at=200\n",
        )
        .unwrap();
        let items = recent_work(&dir).unwrap();
        assert_eq!(items[0].repo, "acme/two");
        assert_eq!(items[1].repo, "acme/one");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn lists_every_run_of_the_same_thread() {
        let dir = std::env::temp_dir().join(format!(
            "breeze-work-runs-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(dir.join("task-1")).unwrap();
        std::fs::create_dir_all(dir.join("task-2")).unwrap();
        write_text(
            &dir.join("task-1/task.env"),
            "repo=acme/one\ntitle=pr\nstatus=handled\nsource=author-follow\nthread_key=/repos/acme/one/pulls/77\nfinished_at=100\n",
        )
        .unwrap();
        write_text(
            &dir.join("task-2/task.env"),
            "repo=acme/one\ntitle=pr\nstatus=skipped\nsource=author-follow\nthread_key=/repos/acme/one/pulls/77\nfinished_at=300\n",
        )
        .unwrap();
        let items = recent_work(&dir).unwrap();
        assert_eq!(items.len(), 2);
        assert_eq!(items[0].status, "skipped");
        assert_eq!(items[1].status, "handled");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn includes_tasks_that_only_have_a_summary() {
        let mut meta = HashMap::new();
        meta.insert("status".to_string(), "timed_out".to_string());
        meta.insert(
            "summary".to_string(),
            "codex agent exited with status 1".to_string(),
        );
        let item = work_item_from_metadata("task-1".to_string(), meta).unwrap();
        assert_eq!(item.status, "timed_out");
        assert_eq!(item.title, "codex agent exited with status 1");
        assert!(item.repo.is_empty());
    }

    #[test]
    fn snapshot_fills_in_a_task_without_task_env() {
        let dir = std::env::temp_dir().join(format!(
            "breeze-work-snapshot-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(dir.join("task-live/snapshot")).unwrap();
        write_text(
            &dir.join("task-live/snapshot/task-summary.env"),
            "repo=acme/one\ntitle=live pr\nthread_key=/repos/acme/one/pulls/9\nupdated_at=2026-08-20T02:40:48Z\n",
        )
        .unwrap();
        let items = recent_work(&dir).unwrap();
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].status, "running");
        assert_eq!(items[0].repo, "acme/one");
        assert_eq!(items[0].title, "live pr");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
