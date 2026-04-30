// Copyright (c) 2024 Lagana Consulting. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution is prohibited.
namespace Collector.Core;

public sealed record AccessGapRow(
    string Dataset,
    string Metric,
    string Status,
    string Reason,
    string Needed
);
