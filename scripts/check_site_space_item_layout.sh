#!/usr/bin/env bash
set -u

cell_file="SunSmart/Main/Space/View/SpacesViewCell.swift"
site_file="SunSmart/Main/Site/Controller/SiteViewController.swift"
failures=0

expect() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if ! grep -Fq "$pattern" "$file"; then
    printf 'FAIL: %s\n' "$message"
    failures=$((failures + 1))
  fi
}

expect "$cell_file" 'timeLabel.numberOfLines = 1' 'timeLabel should stay single-line.'
expect "$cell_file" 'timeLabel.lineBreakMode = .byTruncatingTail' 'timeLabel should truncate long dates instead of expanding layout.'
expect "$cell_file" 'make.top.equalTo(schedulesLabel.snp.bottom).offset(SCRYFrom(4))' 'timeLabel should be vertically chained below schedulesLabel.'
expect "$cell_file" 'make.bottom.equalTo(iconImageView).priority(.high)' 'timeLabel should prefer aligning to the image bottom when space allows.'
expect "$cell_file" 'make.bottom.lessThanOrEqualTo(contentView).offset(SCRYFrom(-12))' 'timeLabel should remain inside the Space card when compact iPad heights need more room.'
expect "$site_file" 'let itemH = isIPad ? max(SCRYFrom(192), 192) : SCRYFrom(192)' 'iPad Space item height should scale but never be below 192pt.'
expect "$site_file" 'return CGSizeMake(itemW, itemH)' 'Space item size should return the calculated height.'

if [ "$failures" -gt 0 ]; then
  exit 1
fi

printf 'PASS: Site Space item layout keeps Schedules and date separated.\n'
