struct Entry
{
	const char *Key;
	const char *Path;
	const struct Entry *Next;
};

extern struct Entry *g_Entries;

void ReadManifest(const char *manifestDir);
void ReadManifestPath(const char *manifestPath);
void LinkFiles(const char *manifestDir);
void LinkFilesTree(const char *manifestDir);
const char *GetManifestDir();
const char *GetManifestPath();
void LinkHostFxr(const char *manifestDir);
int IsVerbose();

char *GetLinkedMonoLauncher(const char *manifestDir);

#ifndef _MSC_VER
void PrepareExe(const char *manifestDir);
void PrepareTestExe(const char *manifestDir);
int cp(const char *to, const char *from);
#endif
