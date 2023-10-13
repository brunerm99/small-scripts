#!/bin/env nu
# gelp.nu - yet another git helper
# TODO: Make database to store usage numbers and sort selection by number of recent uses

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
export def-env "gelp select" [] -> record {
  echo "Gathering projects..."
  let docker_info = docker-info
  let usage = (gelp get-project-history ~/.local/share/gelp/history.db projects) # TODO: update to pull path from environment
  mut projects = (
    cd $env.HOME; ls documents/*/.git | 
    append (ls .gitclones/*/.git) | 
    insert project_dir { |it| $env.HOME | path join ($it.name | path dirname) } |
    join ($docker_info | rename -c [Source project_dir]) project_dir --left | 
    rename -b { str downcase | str trim | str replace -a ' ' '_' } 
  )
  if not ($usage | is-empty) {
    $projects = (
      $projects | 
        join (
          $usage | 
          reject id | 
          rename -c [name project_dir] | 
          update last_used { || into datetime }
        ) project_dir --left | 
      sort-by uses
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
  let action = (["edit", "git", "cd", "open remote"] | input list -f)
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
export def "gelp update-uses" [
  project: record # Project to record in database
  db_path: path # Database path
] {
  open $db_path | query db $"
    INSERT INTO projects 
      \(name, last_used, uses\)
      VALUES \(
        '($project.project_dir)', 
        '(date now | format date "%Y-%m-%dT%H:%M:%S")', 
        1
      \)
      ON CONFLICT \(name\) DO UPDATE SET 
        uses = uses + excluded.uses,
        last_used = '(date now | format date "%Y-%m-%dT%H:%M:%S")';
  "
}

# Get project history
# TODO: Pull path, table name from environment
export def "gelp get-project-history" [
  db_path: path # Database path
  table_name: string # Database table name
] {
  open $db_path | query db $"
    SELECT * FROM ($table_name);
  "
}

# Create SQLite database
export def "gelp create-db" [
  db_path: path # Database path
] {
  mkdir ($db_path | path dirname)
  touch $db_path
  open $db_path | query db "
    CREATE TABLE IF NOT EXISTS projects (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      uses INTEGER,
      last_used TEXT NOT NULL
    );
  "
}

export def init [] { "not implemented" }

# gelp.nu - yet another git helper
export def-env main [] { 
  let project = (gelp select)
  if ($project | is-empty) { return }
  run-action $project
}
