# AGENTS.md

## 项目目标
使用 SwiftUI（iOS 17+）开发一个短剧 App，包含 3 个 Tab 页面：
1. 首页
2. 剧场
3. 我的

---

## 技术约束
- 使用 SwiftUI
- 支持 iOS 17 及以上
- 不使用第三方库
- 如使用 ObservableObject，请 import Combine

---

## API 约束（必须严格遵守）
### 首页 API
接口地址：
`https://zzz-pet.oss-cn-hangzhou.aliyuncs.com/api/drama.json`

`drama.json` 示例格式（以此为准）：
```json
{
  "dramas": [
    {
      "dramaId": "drama_001",
      "title": "xxx",
      "poster": "xxx.JPG",
      "tags": ["奇幻", "民国"],
      "description": "",
      "totalEpisodes": 25,
      "episodes": [
        {
          "episodeNumber": 1,
          "title": "第1集",
          "videoUrl": "xxx.mp4",
          "duration": 78,
          "aspectRatio": 0.5625
        }
      ]
    }
  ]
}
```

### 剧场 API
接口地址：
`https://zzz-pet.oss-cn-hangzhou.aliyuncs.com/api/theater.json`

`theater.json` 示例格式（以此为准）：
```json
{
  "categories": [
    {
      "categoryId": "discover",
      "title": "Find",
      "titleZh": "找剧"
    },
    {
      "categoryId": "comic",
      "title": "Comic",
      "titleZh": "漫剧"
    },
    {
      "categoryId": "movie",
      "title": "Movie",
      "titleZh": "电影"
    },
    {
      "categoryId": "tv",
      "title": "TV Series",
      "titleZh": "电视剧"
    }
  ],
  "sections": [
    {
      "categoryId": "discover",
      "dramas": [
        {
          "dramaId": "drama_001",
          "title": "xxx",
          "poster": "xxx.JPG",
          "tags": ["奇幻", "民国"],
          "description": "",
          "totalEpisodes": 25,
          "episodes": [
            {
              "episodeNumber": 1,
              "title": "第1集",
              "videoUrl": "xxx.mp4",
              "duration": 78,
              "aspectRatio": 0.5625
            }
          ]
        }
      ]
    }
  ]
}
```
---


## 播放规则
- 共享统一的播放管理器
- 首页预览、完整短剧播放页、横屏全屏页之间需要同步播放进度
- 切换页面时尽量复用播放状态
- 不可见页面的播放器应暂停或释放，避免多个播放器同时工作
- 倍速设置应作用于当前正在播放的视频
- 退出横屏全屏后，应保留当前播放位置


---

## 交付要求
每次完成任务后：
1. 说明新增或修改了哪些文件
2. 保证项目仍然可编译运行