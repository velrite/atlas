class JobRecord {
  final String jobId;
  final String status;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const JobRecord({
    required this.jobId,
    required this.status,
    required this.payload,
    required this.createdAt,
  });

  factory JobRecord.fromJson(Map<String, dynamic> json) {
    return JobRecord(
      jobId: json['jobId'] as String,
      status: json['status'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
