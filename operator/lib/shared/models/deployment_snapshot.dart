enum RevisionSource { kubeApi, git, artifactRegistry }

class DeploymentSnapshot {
  final int revisionIndex;
  final String imageTag;
  final String rolloutPhase;
  final int? currentStepIndex;
  final String gitCommit;
  final RevisionSource sourceOfTruth;

  const DeploymentSnapshot({
    required this.revisionIndex,
    required this.imageTag,
    required this.rolloutPhase,
    this.currentStepIndex,
    required this.gitCommit,
    required this.sourceOfTruth,
  });

  factory DeploymentSnapshot.fromJson(Map<String, dynamic> json) {
    return DeploymentSnapshot(
      revisionIndex: json['revisionIndex'] as int,
      imageTag: json['imageTag'] as String,
      rolloutPhase: json['rolloutPhase'] as String,
      currentStepIndex: json['currentStepIndex'] as int?,
      gitCommit: json['gitCommit'] as String,
      sourceOfTruth: RevisionSource.values.byName(json['sourceOfTruth'] as String),
    );
  }
}
