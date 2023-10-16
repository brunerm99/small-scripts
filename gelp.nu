#!/bin/env nu
# gelp.nu - yet another git helper
# Dependencies: fd-find
use utils.nu [venumerate, not-implemented]

export def parse-remote-url [
  repo_path: path # FS repo path
] {
  let git_remote = git -C $repo_path remote get-url origin
  do -i { $git_remote | url parse | url join } | default (    
    $git_remote | 
      parse '{version_control}@{host}:{username}/{repo}.git' | 
      get 0 | 
      insert "scheme" "https" | 
      insert "path" $"($in.username)/($in.repo)" | 
      url join
    )
}
  
export def docker-info [] {
  docker ps | 
    from ssv | 
    insert _ { 
      docker inspect -f '{{ json .Mounts }}' (
        $in | get "CONTAINER ID"
      ) | 
      from json | 
      get 0 
    } |
    flatten
}

# Select project to open
export def-env select [
  --exclude: list<string> # List of directories / files to exclude from project search TODO: not implemented
] -> record {
  if not ($exclude | is-empty) { not-implemented "exclude" }

  echo "Gathering projects..."
  let docker_info = docker-info
  let usage = (get-project-history) 

  mut projects = {name: (fd -Hap -g "**/.git" $"($env.HOME)" -E ".cache" -E ".local" -E ".cargo" | lines) } | 
    flatten | 
    insert project_dir { $in | get name | path dirname } |
    join ($docker_info | rename -c [Source project_dir]) project_dir --left | 
    rename -b { str downcase | str trim | str replace -a ' ' '_' } 

  if not ($usage | is-empty) {
    $projects = (
      $projects | 
        join (
          $usage | 
          reject id | 
          update last_used { || into datetime }
        ) project_dir --left | 
      default 0 uses |
      sort-by uses -r
    )
  }
  let project_idx = (
    $projects | 
    each { 
      if not ($in | get -i image | is-empty) { 
        $"($in.project_dir | path basename) \((ansi g)container: (ansi reset)($in.image)\)" 
      } else { 
        $"($in.project_dir | path basename)" 
      }
    } |
    venumerate |
    input list -f |
    split row ' ' | 
    first | 
    if ($in | is-empty) { return } else { into int }  
  )
  let project = ($projects | get ($project_idx - 1))  
  $project
}

# Run action on project
def-env run-action [
  project: record # Project to run action on 
] {
  let action = (["edit", "git", "cd", "open remote"] | input list -f $"Action for ($project.project_dir | path basename):")
  update-uses $project ~/.local/share/gelp/history.db
  if ($action == "edit") {
    hx $project.project_dir
  } else if ($action == "git") { 
    gitui -d $project.project_dir
  } else if ($action == "cd") {
    cd $project.project_dir
  } else if ($action == "open remote") {
    xdg-open (parse-remote-url $project.project_dir)
  }
  
}

### Database

# Update number of uses of a project
export def update-uses [
  project: record # Project to record in database
  db_path: path # Database path
] {
  open $db_path | query db $"
    INSERT INTO projects 
      \(project_dir, last_used, uses\)
      VALUES \(
        '($project.project_dir)', 
        '(date now | format date "%Y-%m-%dT%H:%M:%S")', 
        1
      \)
      ON CONFLICT \(project_dir\) DO UPDATE SET 
        uses = uses + excluded.uses,
        last_used = '(date now | format date "%Y-%m-%dT%H:%M:%S")';
  "
}

# Get project history
export def get-project-history [] {
  create-env
  open $env.gelp_db_dir | query db $"SELECT * FROM projects;"
}

# Create SQLite database
export def create-db [
  db_path: path # Database path
] {
  mkdir ($db_path | path dirname)
  touch $db_path
  open $db_path | query db "
    CREATE TABLE IF NOT EXISTS projects (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      project_dir TEXT NOT NULL UNIQUE,
      uses INTEGER,
      last_used TEXT NOT NULL
    );
  "
}

# Get last-used project
def get-last-used [] {
  get-project-history | 
    update last_used {|| into datetime} | 
    sort-by last_used | 
    last
}

# Clear project use history
export def clear-history [
  db_path: path # Database path
] {
  if (input "Are you sure? ") == "y" {
    let num_entries = (open $db_path | query db $"
      SELECT * FROM projects;
      DELETE FROM projects;
    " | length)
    open $db_path | query db $"DELETE FROM projects;"
    print $"($num_entries) row(s) deleted"
  }
}

export def init [] { "not implemented" }

export def-env create-env [] {
  $env.gelp_dir = ($env | get -i gelp_dir | default ($env.HOME | path join ".local/share/gelp"))
  $env.gelp_db_dir = ($env.gelp_dir | path join "history.db")
  $env.gelp_projects_cache = ($env.gelp_dir | path join "projects_cache.nuon")
 }

def update-db [] {
  
}

# gelp.nu - yet another git helper
export def-env main [
  --last (-l) # Bypass selector, use last project
  --no-cache (-n) # Don't use cached projects
] { 
  if not ($no_cache | is-empty) { not-implemented "no_cache" }

  let project = if $last { get-last-used } else { (select) } 
  if ($project | is-empty) { print "No project specified"; return }
  run-action $project
}
