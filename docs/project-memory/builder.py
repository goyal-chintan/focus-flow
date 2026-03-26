#!/usr/bin/env python3
"""
Process FocusFlow session history and populate project memory.
Converts session summaries into structured decision log and markdown documentation.
"""

import sqlite3
import json
import re
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

class ProjectMemoryBuilder:
    """Build comprehensive project memory from session history."""
    
    def __init__(self, db_path: str, docs_path: str):
        self.db_path = db_path
        self.docs_path = Path(docs_path)
        self.conn = sqlite3.connect(db_path)
        self.conn.row_factory = sqlite3.Row
        
    def add_session(self, session_id: str, session_index: int, theme: str,
                   description: str, key_outcomes: List[str], 
                   decisions_made: List[Dict]) -> None:
        """Add a session summary and its decisions to the database."""
        
        cursor = self.conn.cursor()
        
        # Add session summary
        cursor.execute("""
            INSERT OR REPLACE INTO session_summary 
            (session_id, session_index, theme, description, key_outcomes, decisions_made)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (
            session_id,
            session_index,
            theme,
            description,
            json.dumps(key_outcomes),
            json.dumps(decisions_made)
        ))
        
        # Add individual decisions
        for i, decision in enumerate(decisions_made):
            decision_id = f"{session_id}_{i}"
            cursor.execute("""
                INSERT OR REPLACE INTO decisions
                (id, session_id, category, title, description, rationale, 
                 outcome, status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                decision_id,
                session_id,
                decision.get('category', 'General'),
                decision.get('title', ''),
                decision.get('description', ''),
                decision.get('rationale', ''),
                decision.get('outcome', ''),
                'active'
            ))
        
        self.conn.commit()
    
    def add_design_pattern(self, pattern_name: str, description: str,
                          category: str, examples: List[str],
                          rationale: str, created_in_session: str) -> None:
        """Add a design pattern to the database."""
        
        cursor = self.conn.cursor()
        pattern_id = pattern_name.lower().replace(' ', '_')
        
        cursor.execute("""
            INSERT OR REPLACE INTO design_patterns
            (id, pattern_name, description, category, examples, rationale, created_in_session)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (
            pattern_id,
            pattern_name,
            description,
            category,
            json.dumps(examples),
            rationale,
            created_in_session
        ))
        
        self.conn.commit()
    
    def get_decisions_by_category(self, category: str) -> List[Dict]:
        """Retrieve all decisions in a category."""
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT * FROM decisions WHERE category = ? ORDER BY decision_date
        """, (category,))
        return [dict(row) for row in cursor.fetchall()]
    
    def get_session_decisions(self, session_id: str) -> List[Dict]:
        """Retrieve all decisions made in a specific session."""
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT * FROM decisions WHERE session_id = ? ORDER BY decision_date
        """, (session_id,))
        return [dict(row) for row in cursor.fetchall()]
    
    def generate_timeline_markdown(self) -> str:
        """Generate timeline markdown from database."""
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT session_id, session_index, theme, description, key_outcomes, decisions_made
            FROM session_summary
            ORDER BY session_index
        """)
        
        md = "# Project Evolution Timeline\n\n"
        md += "## Session-by-Session Breakdown\n\n"
        
        for row in cursor.fetchall():
            md += f"### Session {row['session_index']}: {row['theme']}\n"
            md += f"**ID:** {row['session_id']}\n\n"
            md += f"{row['description']}\n\n"
            
            if row['key_outcomes']:
                outcomes = json.loads(row['key_outcomes'])
                md += "**Key Outcomes:**\n"
                for outcome in outcomes:
                    md += f"- {outcome}\n"
                md += "\n"
            
            if row['decisions_made']:
                decisions = json.loads(row['decisions_made'])
                md += "**Decisions Made:**\n"
                for decision in decisions:
                    md += f"- {decision.get('title', 'Untitled')}\n"
                md += "\n"
            
            md += "---\n\n"
        
        return md
    
    def close(self):
        """Close database connection."""
        self.conn.close()


def parse_session_summary(content: str) -> Optional[Dict]:
    """Parse session summary from checkpoint or plan markdown."""
    # This will be implemented based on actual session format
    pass


if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1:
        db_path = sys.argv[1]
    else:
        db_path = "DECISION_LOG.db"
    
    builder = ProjectMemoryBuilder(
        db_path,
        Path(__file__).parent
    )
    
    # Example: Add a session
    # builder.add_session(
    #     session_id="example",
    #     session_index=1,
    #     theme="Initial Setup",
    #     description="Bootstrapped project structure and initial timer logic",
    #     key_outcomes=["Project scaffold created", "Basic timer working"],
    #     decisions_made=[...]
    # )
    
    builder.close()
    print(f"Project memory builder initialized with {db_path}")
