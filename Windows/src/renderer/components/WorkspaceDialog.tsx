import React, { useState } from 'react';
import { useStore } from '../store/AppStore';
import { Icon } from './Icon';
import { CloseGlyph } from './Symbols';

export function WorkspaceDialog(): JSX.Element {
  const { state, actions, derived } = useStore();
  const { tr } = derived;
  const [vaultName, setVaultName] = useState('');
  const [projectName, setProjectName] = useState('');
  const [renaming, setRenaming] = useState<{ kind: 'vault' | 'project'; id: string; value: string } | null>(null);

  const projects = state.projects.filter((project) => project.vaultId === state.activeVaultId);

  const commitRename = (): void => {
    if (!renaming) return;
    if (renaming.kind === 'vault') actions.renameVault(renaming.id, renaming.value);
    else actions.renameProject(renaming.id, renaming.value);
    setRenaming(null);
  };

  return (
    <div className="overlay dialog-overlay" onPointerDown={(event) => {
      if (event.target === event.currentTarget) actions.setWorkspacesOpen(false);
    }}>
      <div className="dialog workspace-dialog" role="dialog" aria-modal="true" aria-label={tr('工作区与项目')}>
        <div className="dialog-head">
          <div>
            <h2>{tr('工作区与项目')}</h2>
            <p>{tr('工作区是独立的知识库；项目用于在当前工作区内组织笔记。')}</p>
          </div>
          <button
            type="button"
            className="icon-btn tiny"
            aria-label={tr('关闭')}
            onClick={() => actions.setWorkspacesOpen(false)}
          >
            <CloseGlyph size={12} color="var(--text-2)" />
          </button>
        </div>

        <div className="workspace-columns">
          <section className="workspace-column">
            <h3>{tr('知识库')}</h3>
            <div className="workspace-list">
              {state.vaults.map((vault) => (
                <div key={vault.id} className={`workspace-row${vault.id === state.activeVaultId ? ' active' : ''}`}>
                  <Icon name="dock_vault" size={17} muted={vault.id !== state.activeVaultId} />
                  {renaming?.kind === 'vault' && renaming.id === vault.id ? (
                    <input
                      autoFocus
                      className="inline-input"
                      value={renaming.value}
                      onChange={(event) => setRenaming({ ...renaming, value: event.target.value })}
                      onBlur={commitRename}
                      onKeyDown={(event) => {
                        if (event.key === 'Enter') commitRename();
                        if (event.key === 'Escape') setRenaming(null);
                      }}
                    />
                  ) : (
                    <button
                      type="button"
                      className="workspace-name"
                      onClick={() => actions.requestWorkspace(vault.id)}
                    >
                      {vault.name}
                    </button>
                  )}
                  <span className="workspace-count">
                    {state.notes.filter((note) => note.vaultId === vault.id && note.trashedAt === 0).length}
                  </span>
                  <button
                    type="button"
                    className="small-btn ghost"
                    onClick={() => setRenaming({ kind: 'vault', id: vault.id, value: vault.name })}
                  >
                    {tr('重命名')}
                  </button>
                </div>
              ))}
            </div>
            <div className="workspace-create">
              <input
                value={vaultName}
                placeholder={tr('新工作区名称')}
                onChange={(event) => setVaultName(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === 'Enter') {
                    actions.createVault(vaultName);
                    setVaultName('');
                  }
                }}
              />
              <button
                type="button"
                className="small-btn"
                onClick={() => {
                  actions.createVault(vaultName);
                  setVaultName('');
                }}
              >
                {tr('新建工作区')}
              </button>
            </div>
          </section>

          <section className="workspace-column">
            <h3>{derived.activeVault?.name ?? tr('工作区')} · {tr('项目')}</h3>
            <div className="workspace-list">
              {projects.length === 0 ? (
                <p className="workspace-empty">{tr('还没有项目。项目会出现在左侧知识库列表中。')}</p>
              ) : null}
              {projects.map((project) => (
                <div key={project.id} className={`workspace-row${project.id === state.activeProjectId ? ' active' : ''}`}>
                  <Icon name="folder" size={16} />
                  {renaming?.kind === 'project' && renaming.id === project.id ? (
                    <input
                      autoFocus
                      className="inline-input"
                      value={renaming.value}
                      onChange={(event) => setRenaming({ ...renaming, value: event.target.value })}
                      onBlur={commitRename}
                      onKeyDown={(event) => {
                        if (event.key === 'Enter') commitRename();
                        if (event.key === 'Escape') setRenaming(null);
                      }}
                    />
                  ) : (
                    <button
                      type="button"
                      className="workspace-name"
                      onClick={() => {
                        actions.setActiveProject(project.id);
                        actions.setWorkspacesOpen(false);
                      }}
                    >
                      {project.name}
                    </button>
                  )}
                  <span className="workspace-count">
                    {state.notes.filter((note) => note.projectId === project.id && note.trashedAt === 0).length}
                  </span>
                  <button
                    type="button"
                    className="small-btn ghost"
                    onClick={() => setRenaming({ kind: 'project', id: project.id, value: project.name })}
                  >
                    {tr('重命名')}
                  </button>
                  <button type="button" className="small-btn ghost danger" onClick={() => actions.deleteProject(project.id)}>
                    {tr('删除')}
                  </button>
                </div>
              ))}
            </div>
            <div className="workspace-create">
              <input
                value={projectName}
                placeholder={tr('新项目名称')}
                onChange={(event) => setProjectName(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === 'Enter') {
                    actions.createProject(projectName);
                    setProjectName('');
                  }
                }}
              />
              <button
                type="button"
                className="small-btn"
                onClick={() => {
                  actions.createProject(projectName);
                  setProjectName('');
                }}
              >
                {tr('新建项目')}
              </button>
            </div>
          </section>
        </div>

        <div className="dialog-foot">
          <span className="foot-hint">{tr('使用「重命名」按钮修改名称。删除项目不会删除笔记。')}</span>
          <button type="button" className="primary-btn" onClick={() => actions.setWorkspacesOpen(false)}>
            {tr('完成')}
          </button>
        </div>
      </div>
    </div>
  );
}
