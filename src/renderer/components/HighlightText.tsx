import React from 'react';
import { highlightSegments } from '../core/search';

export interface HighlightTextProps {
  text: string;
  query: string;
  className?: string;
}

/** Renders text with search-hit keywords wrapped in semantic <mark> highlights. */
export const HighlightText: React.FC<HighlightTextProps> = ({ text, query, className }) => {
  const segments = highlightSegments(text, query);
  if (segments.length === 0) return <span className={className}>{text}</span>;
  return (
    <span className={className}>
      {segments.map((seg, index) =>
        seg.hit ? (
          <mark key={`${index}-${seg.text}`} className="search-hit">
            {seg.text}
          </mark>
        ) : (
          <React.Fragment key={`${index}-${seg.text}`}>{seg.text}</React.Fragment>
        )
      )}
    </span>
  );
};
