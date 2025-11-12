#!/usr/bin/env python3
import argparse
import math
from datetime import datetime

def ceil_to_2_decimal(x):
    """Round up the number to 2 decimal places (ceiling at the 3rd decimal digit)."""
    return math.ceil(x * 100) / 100.0

def calculate_time_difference(date_str1, date_str2):
    """Calculate time difference between two datetime strings in multiple units."""
    fmt = "%Y-%m-%d %H:%M:%S"
    try:
        dt1 = datetime.strptime(date_str1, fmt)
        dt2 = datetime.strptime(date_str2, fmt)
    except ValueError as e:
        raise ValueError(f"Invalid date format. Please use 'YYYY-MM-DD HH:MM:SS'. Details: {e}")

    diff = abs(dt2 - dt1)
    total_seconds_exact = diff.total_seconds()

    # Compute exact values in different units
    total_minutes_exact = total_seconds_exact / 60
    total_hours_exact = total_seconds_exact / 3600
    total_days_exact = total_seconds_exact / (24 * 3600)

    # Apply ceiling to 2 decimal places
    total_seconds = ceil_to_2_decimal(total_seconds_exact)
    total_minutes = ceil_to_2_decimal(total_minutes_exact)
    total_hours = ceil_to_2_decimal(total_hours_exact)
    total_days = ceil_to_2_decimal(total_days_exact)

    return {
        "total_seconds": total_seconds,
        "total_minutes": total_minutes,
        "total_hours": total_hours,
        "total_days": total_days,
    }

def format_two_decimal(value):
    """Format a number to always show exactly 2 decimal places (e.g., 5 → '5.00')."""
    return f"{value:.2f}"

def main():
    parser = argparse.ArgumentParser(
        description="Calculate time interval between two datetimes (format: 'YYYY-MM-DD HH:MM:SS'), "
                    "with results rounded up to 2 decimal places."
    )
    parser.add_argument("date1", help="First datetime, e.g., '2025-11-10 19:01:57'")
    parser.add_argument("date2", help="Second datetime, e.g., '2025-11-11 14:22:00'")

    args = parser.parse_args()

    try:
        result = calculate_time_difference(args.date1, args.date2)
        print(f"Date 1: {args.date1}")
        print(f"Date 2: {args.date2}")
        print(f"Total seconds: {format_two_decimal(result['total_seconds'])}")
        print(f"Total minutes: {format_two_decimal(result['total_minutes'])}")
        print(f"Total hours:   {format_two_decimal(result['total_hours'])}")
        print(f"Total days:    {format_two_decimal(result['total_days'])}")
    except ValueError as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
