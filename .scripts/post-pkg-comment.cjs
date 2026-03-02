/**
 * Post a PR comment with package download links and size comparison
 */
module.exports = async ({
  github,
  context,
  hasStandard = true,
  hasNoLib = true,
  noLibUrl,
  libsUrl,
  latestReleaseStandardSize,
  testPkgStandardSize,
  latestReleaseNoLibSize,
  testPkgNoLibSize,
}) => {
  const commentIdentifier = "### 📦 Packaged ZIP files";

  // Format bytes to human-readable size
  function formatBytes(bytes) {
    if (bytes === 0) return "0 B";
    const k = 1024;
    const sizes = ["B", "KB", "MB", "GB"];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + " " + sizes[i];
  }

  // Calculate size change with handling for first release
  function getSizeChange(oldSize, newSize) {
    if (oldSize === 0) {
      return {
        emoji: "🆕",
        text: formatBytes(newSize),
        detailed: "First release",
      };
    }
    const diff = newSize - oldSize;
    const percentChange = ((diff / oldSize) * 100).toFixed(1);
    const emoji = diff > 5120 ? "⚠️" : diff < 0 ? "🟢" : "➡️"; // 5KB threshold for warning
    const sign = diff > 0 ? "+" : "";
    return {
      emoji,
      text: formatBytes(newSize),
      detailed: `${formatBytes(oldSize)} ➡️ ${formatBytes(newSize)} (${sign}${percentChange}%)`,
    };
  }

  const standardChange = getSizeChange(
    latestReleaseStandardSize,
    testPkgStandardSize,
  );
  const nolibChange = getSizeChange(latestReleaseNoLibSize, testPkgNoLibSize);

  const hasReleases =
    latestReleaseStandardSize > 0 || latestReleaseNoLibSize > 0;

  const lastUpdated = new Date().toLocaleString("en-US", {
    timeZone: "UTC",
    hour12: true,
  });

  let commentBody = `${commentIdentifier}\n\n`;

  // If neither package type exists, show an error message
  if (!hasStandard && !hasNoLib) {
    commentBody += `⚠️ No package files were generated. Check the workflow logs for errors.\n\n`;
  } else {
    commentBody += `| Package | Size | ${hasReleases ? "Change" : "Status"} |\n`;
    commentBody += `|---------|------|${hasReleases ? "--------" : "--------"}|\n`;

    if (hasStandard) {
      const label = hasNoLib ? "With Libraries" : "Package";
      commentBody += `| [${label}](${libsUrl}) | ${standardChange.text} | ${standardChange.emoji} ${standardChange.detailed} |\n`;
    }

    if (hasNoLib) {
      commentBody += `| [NoLib](${noLibUrl}) | ${nolibChange.text} | ${nolibChange.emoji} ${nolibChange.detailed} |\n`;
    }

    commentBody += `\n`;
  }

  commentBody += `*Last Updated: ${lastUpdated} (UTC)*`;

  const { data: comments } = await github.rest.issues.listComments({
    issue_number: context.issue.number,
    owner: context.repo.owner,
    repo: context.repo.repo,
  });

  const existingComment = comments.find((comment) =>
    comment.body.includes(commentIdentifier),
  );

  if (existingComment) {
    await github.rest.issues.updateComment({
      comment_id: existingComment.id,
      owner: context.repo.owner,
      repo: context.repo.repo,
      body: commentBody,
    });
  } else {
    await github.rest.issues.createComment({
      issue_number: context.issue.number,
      owner: context.repo.owner,
      repo: context.repo.repo,
      body: commentBody,
    });
  }
};
