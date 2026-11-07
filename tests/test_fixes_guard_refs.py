"""Exercise real pre-push ref batches against actual Git commit graphs."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
BASH=os.environ.get('YMIR_BASH') or shutil.which('bash')
ZERO='0'*40

@unittest.skipUnless(BASH and shutil.which('git'),'requires Bash and Git')
class FixesGuardRefsTest(unittest.TestCase):
    def test_every_branch_is_judged_in_both_orders(self):
        with tempfile.TemporaryDirectory(prefix='fixes-refs-') as temporary:
            root=Path(temporary)
            for folder in ('.pi','RULES','bin/gates/guards','docs/fixes/agents'):
                (root/folder).mkdir(parents=True,exist_ok=True)
            shutil.copyfile(ROOT/'bin/gates/guards/fixes-guard.sh',root/'bin/gates/guards/fixes-guard.sh')
            env={k:v for k,v in os.environ.items() if k!='YMIR_SKIP_FIXES_GUARD'}
            env.update(GIT_AUTHOR_NAME='Fixture',GIT_AUTHOR_EMAIL='fixture@example.invalid',GIT_COMMITTER_NAME='Fixture',GIT_COMMITTER_EMAIL='fixture@example.invalid')
            def git(*args):
                return subprocess.check_output(['git',*args],cwd=root,env=env).decode().strip()
            git('init','-q','-b','main');git('config','core.autocrlf','false');git('add','--','.');git('commit','-qm','base')
            base=git('rev-parse','HEAD');git('update-ref','refs/remotes/origin/main',base)
            def branch(name,note):
                git('checkout','-qb',name,base)
                (root/'docs/fixes/agents').mkdir(parents=True,exist_ok=True)
                (root/'change.txt').write_text(name,encoding='utf-8')
                if note: (root/f'docs/fixes/agents/2026-01-01-{name}.md').write_text('# Fixture record.\n',encoding='utf-8')
                git('add','--','.');git('commit','-qm',name)
                return git('rev-parse','HEAD')
            good=branch('recorded',True);good2=branch('recorded-two',True);bad=branch('unrecorded',False)
            def row(name,sha,remote=ZERO,kind='heads'):
                return f'refs/{kind}/{name} {sha} refs/{kind}/{name} {remote}\n'
            def check(rows,expected,manual=False):
                args=[BASH,(root/'bin/gates/guards/fixes-guard.sh').as_posix()]
                if manual: args.append('--check')
                result=subprocess.run(args,input=rows.encode(),env=env,cwd=root,capture_output=True)
                output=(result.stdout+result.stderr).decode('utf-8',errors='replace')
                self.assertEqual(result.returncode,expected,output)
                return output
            with self.subTest('bad last'): check(row('good',good)+row('bad',bad),1)
            with self.subTest('bad first'): check(row('bad',bad)+row('good',good),1)
            with self.subTest('all recorded'): check(row('good',good)+row('good2',good2),0)
            with self.subTest('public ancestor alias'): check(row('alias',base),0)
            with self.subTest('unrecorded new code'): check(row('bad',bad),1)
            with self.subTest('public pointer update'): check(row('alias',base,bad),0)
            with self.subTest('tags'): check(row('tag',bad,kind='tags'),0)
            with self.subTest('deletions'): check(row('deleted',ZERO,bad),0)
            with self.subTest('mixed tag and bad'): check(row('bad',bad)+row('tag',good,kind='tags'),1)
            with self.subTest('manual check remains strict'): check('',1,manual=True)
            unrelated=git('commit-tree',git('rev-parse',bad+'^{tree}'),'-m','unrelated unrecorded')
            with self.subTest('no shared base still requires record'): check(row('unrelated',unrelated),1)
            recorded_root=git('commit-tree',git('rev-parse',good+'^{tree}'),'-m','unrelated recorded')
            with self.subTest('recorded unrelated history'): check(row('recorded-root',recorded_root),0)

if __name__=='__main__': unittest.main()
